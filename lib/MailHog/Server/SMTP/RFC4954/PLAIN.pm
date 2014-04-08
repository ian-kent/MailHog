package MailHog::Server::SMTP::RFC4954::PLAIN;

# RFC4616 SASL PLAIN

use Modern::Perl;
use Moose;

use MIME::Base64 qw/ decode_base64 encode_base64 /;

has 'rfc' => ( is => 'rw', isa => 'MailHog::Server::SMTP::RFC4954' );

#------------------------------------------------------------------------------

sub helo {
	my ($self, $session) = @_;

	if(!$session->{tls_enabled}) {
        unless($session->smtp->config->{extensions}->{auth}->{plain}->{allow_no_tls}) {
		    return undef;
        }
	}

	return "PLAIN";
}

#------------------------------------------------------------------------------

sub initial_response {
	my ($self, $session, $args) = @_;

    if(!$session->{tls_enabled}) {
        unless($session->smtp->config->{extensions}->{auth}->{plain}->{allow_no_tls}) {
            $session->log("PLAIN authentication received but connection is not TLS protected");
            $session->respond($MailHog::Server::SMTP::ReplyCodes{COMMAND_PARAMETER_NOT_IMPLEMENTED}, "Error: authentication failed: must use a TLS connection");
            return;
        }
    }

	if(!$args) {
		$session->log("PLAIN received no args in initial response, returning 334");
		$session->respond($MailHog::Server::SMTP::ReplyCodes{SERVER_CHALLENGE});
		return;
	}

	return $self->data($session, $args);
}

#------------------------------------------------------------------------------

sub data {
	my ($self, $session, $data) = @_;

	$session->log("Authenticating using PLAIN mechanism");

	# Decode base64 data
    my $decoded;
    eval {
    	$session->log("Decoding [$data]");
        $decoded = decode_base64($data);
    };

    # If there's an error, or we didn't decode anything
    if($@ || !$decoded) {
    	$session->log("Error decoding base64 string: $@");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Not a valid BASE64 string");
        $session->user(undef);
        $session->state('ACCEPT');
        return;
    }

    # Split at the null byte
    my @parts = split /\0/, $decoded;
    if(scalar @parts != 3) {
    	$session->log("Invalid PLAIN token");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_FAILED}, "authentication failed: another step is needed in authentication");
        $session->user(undef);
        $session->state('ACCEPT');
        return;
    }

    my $username = $parts[0];
    my $identity = $parts[1];
    my $password = $parts[2];

    $session->log("PLAIN: Username [$username], Identity [$identity], Password [$password]");

    if(!$username) {
        $session->log("Setting username to identity");
        $username = $identity;
    }

    my $authed = $session->smtp->get_user($username, $password);

    if(!$authed) {
        $session->log("Authentication failed");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_FAILED}, "PLAIN authentication failed");
        $session->user(undef);
    } else {
    	$session->log("Authentication successful");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_SUCCESSFUL}, "authentication successful");
        $session->user($authed);
    }

    $session->state('ACCEPT');
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;