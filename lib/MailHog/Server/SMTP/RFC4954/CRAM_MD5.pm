package MailHog::Server::SMTP::RFC4954::CRAM_MD5;

# SASL CRAM-MD5 RFC2195

use Modern::Perl;
use Moose;

use Digest::MD5 qw/ md5 md5_base64 /;
use Digest::HMAC_MD5 qw(hmac_md5_hex);
use MIME::Base64 qw/ decode_base64 encode_base64 /;

has 'rfc' => ( is => 'rw', isa => 'MailHog::Server::SMTP::RFC4954' );

#------------------------------------------------------------------------------

sub helo {
	my ($self, $session) = @_;

	return "CRAM-MD5";
}

#------------------------------------------------------------------------------

sub initial_response {
	my ($self, $session, $args) = @_;

	if(!$args) {
		$session->log("CRAM-MD5 received no args in initial response, returning 334");
        my $challenge = "<" . int(rand(10000)) . "." . time . "\@" . $session->smtp->config->{hostname} . ">";
        $session->stash(cram_md5_challenge => $challenge);
        my $md5_challenge = encode_base64($challenge);
        $md5_challenge =~ s/[\r\n]*$//;

        $session->respond($MailHog::Server::SMTP::ReplyCodes{SERVER_CHALLENGE}, $md5_challenge);
		return;
	}

    $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Unexpected parameters for AUTH CRAM-MD5");
    $session->state('ACCEPT');
}

#------------------------------------------------------------------------------

sub data {
	my ($self, $session, $data) = @_;

	$session->log("Authenticating using CRAM-MD5 mechanism");

    $session->log($data);
    my $decoded = decode_base64($data);
    $session->log("Decoded: $decoded");

    my ($user, $pass) = split /\s/, $decoded, 2;

    my $mailbox = $session->smtp->get_user($user, undef);
    my $b64 = hmac_md5_hex($session->stash('cram_md5_challenge'), $mailbox->password);

    $session->log("Username [$user], password [$pass], expected [$b64]");
    
    if($pass ne $b64) {
        $session->log("Authentication failed");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_FAILED}, "CRAM-MD5 authentication failed");
        $session->user(undef);
    } else {
        $session->log("Authentication successful");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_SUCCESSFUL}, "authentication successful");
        $session->user($mailbox);
    }

    $session->state('ACCEPT');
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;