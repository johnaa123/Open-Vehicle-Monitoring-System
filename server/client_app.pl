#!/usr/bin/perl

use Digest::MD5;
use Digest::HMAC;
use Crypt::RC4::XS;
use MIME::Base64;
use IO::Socket::INET;

my $b64tab = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

my $shared_secret = "NETPASS";
my $user_pass = "OVMS";

print STDERR "Shared Secret is: ",$shared_secret,"\n";

#####
##### CONNECT
#####

my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1',
                                 PeerPort => '6867',
                                 Proto    => 'tcp');

#####
##### CLIENT
#####

print STDERR "I am the client\n";

rand;
my $client_token;
foreach (0 .. 21)
  { $client_token .= substr($b64tab,rand(64),1); }
print STDERR "  Client token is  $client_token\n";

my $client_hmac = Digest::HMAC->new($shared_secret, "Digest::MD5");
$client_hmac->add($client_token);
my $client_digest = $client_hmac->b64digest();
print STDERR "  Client digest is $client_digest\n";

print $sock "MP-A 0 $client_token $client_digest TESTCAR\r\n";

my $line = <$sock>;
chop $line;
chop $line;
print STDERR "  Received $line from server\n";
my ($welcome,$crypt,$server_token,$server_digest) = split /\s+/,$line;

print STDERR "  Received $server_token $server_digest from server\n";

my $d_server_digest = decode_base64($server_digest);
my $client_hmac = Digest::HMAC->new($shared_secret, "Digest::MD5");
$client_hmac->add($server_token);
if ($client_hmac->digest() ne $d_server_digest)
  {
  print STDERR "  Client detects server digest is invalid - aborting\n";
  exit(1);
  }
print STDERR "  Client verification of server digest is ok\n";

$client_hmac = Digest::HMAC->new($shared_secret, "Digest::MD5");
$client_hmac->add($server_token);
$client_hmac->add($client_token);
my $client_key = $client_hmac->digest;
print STDERR "  Client version of shared key is: ",encode_base64($client_key,''),"\n";

my $txcipher = Crypt::RC4::XS->new($client_key);
$txcipher->RC4(chr(0) x 1024); # Prime the cipher
my $rxcipher = Crypt::RC4::XS->new($client_key);
$rxcipher->RC4(chr(0) x 1024); # Prime the cipher

my $encrypted = encode_base64($txcipher->RC4("MP-0 A"),'');
print STDERR "  Sending message $encrypted\n";
print $sock "$encrypted\r\n";

my $ptoken = "";
my $pdigest = "";
while(<$sock>)
  {
  chop; chop;
  print STDERR "  Received $_ from server\n";
  my $decoded = $rxcipher->RC4(decode_base64($_));
  print STDERR "  Server message decodes to: ",$decoded,"\n";

  if ($decoded =~ /^MP-0 ET(.+)/)
    {
    $ptoken = $1;
    print STDERR "    Paranoid token $ptoken received\n";
    my $paranoid_hmac = Digest::HMAC->new($user_pass, "Digest::MD5");
    $paranoid_hmac->add($ptoken);
    $pdigest = $paranoid_hmac->digest;
    }
  elsif ($decoded =~ /^MP-0 EM(.)(.*)/)
    {
    my ($code,$data) = ($1,$2);
    my $pmcipher = Crypt::RC4::XS->new($pdigest);
    $pmcipher->RC4(chr(0) x 1024); # Prime the cipher
    $decoded = $pmcipher->RC4(decode_base64($data));
    print STDERR "    Paranoid message $code $decoded\n";
    }
  }
