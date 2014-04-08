package MailHog::Server::SMTP::RFC4954::LOGIN;

# SASL LOGIN - probably not required

use Modern::Perl;
use Moose;

use MIME::Base64 qw/ decode_base64 encode_base64 /;

has 'rfc' => ( is => 'rw', isa => 'MailHog::Server::SMTP::RFC4954' );

#------------------------------------------------------------------------------

sub helo {
	my ($self, $session) = @_;

	return "LOGIN";
}

#------------------------------------------------------------------------------

sub initial_response {
	my ($self, $session, $args) = @_;

	if(!$args) {
		$session->log("LOGIN received no args in initial response, returning 334");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SERVER_CHALLENGE}, "VXNlcm5hbWU6");
		return;
	}

	return $self->data($session, $args);
}

#------------------------------------------------------------------------------

sub data {
	my ($self, $session, $data) = @_;

	$session->log("Authenticating using LOGIN mechanism");

    # Get the username first
	if(!$session->user || !$session->stash('username')) {
        my $username;
        eval {
            $session->log("Decoding data [$data]");
            $username = decode_base64($data);
            $username =~ s/\r?\n$//s;
        };
        if($@ || !$username) {
            $session->log("Error decoding base64 data: $@");

            $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Not a valid BASE64 string");
            $session->state('ACCEPT');
            $session->user(undef);

            delete $session->stash->{username} if $session->stash->{username};
            delete $session->stash->{password} if $session->stash->{password};

            return;
        }

        $session->log("Got username: $username");
        $session->stash(username => $username);
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SERVER_CHALLENGE}, "UGFzc3dvcmQ6");
        return;
    } 

    my $password;
    eval {
        $session->log("Decoding data [$data]");
        $password = decode_base64($data);
        $password =~ s/\r?\n$//s;
    };
    if($@ || !$password) {
        $session->log("Error decoding base64 data: $@");

        $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Not a valid BASE64 string");
        $session->state('ACCEPT');
        $session->user(undef);

        delete $session->stash->{username} if $session->stash->{username};
        delete $session->stash->{password} if $session->stash->{password};
        return;
    }

    $session->log("Got password: $password");
    $session->stash(password => $password);

    $session->log("LOGIN: Username [" . $session->stash('username') . "], Password [$password]");

    my $user = $session->smtp->get_user($session->stash('username'), $password);
    if(!$user) {
        $session->log("Authentication failed");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_FAILED}, "LOGIN authentication failed");
        $session->user(undef);
        delete $session->stash->{username} if $session->stash->{username};
        delete $session->stash->{password} if $session->stash->{password};
    } else {
        $session->log("Authentication successful");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{AUTHENTICATION_SUCCESSFUL}, "authentication successful");
        $session->user($user);
    }

    $session->state('ACCEPT');
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;