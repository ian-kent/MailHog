package MailHog::Server::SMTP::RFC4954;

=head NAME
MailHog::Server::SMTP::RFC4954 - AUTH extension
=cut

use Modern::Perl;
use Moose;

use MailHog::Log;

# TODO require these below
use MailHog::Server::SMTP::RFC4954::PLAIN;
use MailHog::Server::SMTP::RFC4954::LOGIN;
use MailHog::Server::SMTP::RFC4954::CRAM_MD5;

use MIME::Base64 qw/ decode_base64 encode_base64 /;

has 'mechanisms' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

#------------------------------------------------------------------------------

sub register {
	my ($self, $smtp) = @_;

    # Register this RFC
    if(!$smtp->has_rfc('RFC5321')) {
        die "MailHog::Server::SMTP::RFC4954 requires RFC5321";
    }
    $smtp->register_rfc('RFC4954', $self);

    # Register configured mechanisms
    for my $mechanism (keys $smtp->config->{extensions}->{auth}->{mechanisms}) {
        my $class = $smtp->config->{extensions}->{auth}->{mechanisms}->{$mechanism};
        $self->mechanisms->{$mechanism} = $class->new(rfc => $self);
    }

    # Add some reply codes
    $smtp->register_replycode({
        AUTHENTICATION_SUCCESSFUL  => 235,

        SERVER_CHALLENGE           => 334,

        PASSWORD_TRANSITION_NEEDED => 432,

        TEMPORARY_FAILURE          => 454,

        AUTHENTICATION_FAILED     => 535,

        AUTHENTICATION_REQUIRED    => 530,
        AUTHENTICATION_TOO_WEAK    => 534,
        ENCRYPTION_REQUIRED        => 538,
    });

	# Register the AUTH command
	$smtp->register_command(['AUTH'], sub {
        my ($session, $data) = @_;
		$self->auth($session, $data);
	});

    # Replace RFC5321's MAIL command
    $smtp->register_command('MAIL', sub {
        my ($session, $data) = @_;
        $self->mail($session, $data);
    });

    # Register a state hook to capture data
    $smtp->register_state('AUTHENTICATE', sub {
        my ($session) = @_;
        $self->authenticate($session);
    });

    # Add a list of commands to EHLO output
    $smtp->register_helo(sub {
        $self->helo(@_);
    });
}

#------------------------------------------------------------------------------

sub helo {
    my $self = shift;
    
    my $mechanisms = '';
    for my $mech (keys %{$self->mechanisms}) {
        my $helo = $self->mechanisms->{$mech}->helo(@_);
        if($helo) {
            $mechanisms .= ' ' if $mechanisms;
            $mechanisms .= $helo;
        }
    }

    return "AUTH $mechanisms";
}

#------------------------------------------------------------------------------

sub mail {
    my ($self, $session, $data) = @_;

    # TODO need somewhere to store this in the message
    # (and some way of making use of it in MDA)

    if(my ($mailbox) = $data =~ /AUTH=<([^>]*)>/) {
        # Strip off AUTH parameter
        $data =~ s/\s*AUTH=<([^>]*)>//;

        $session->log("Using MAIL from RFC4954, auth provided [$mailbox], remaining data [$data]");

        # If client isn't trusted, reset the AUTH=<> parameter (but still include it!)
        if(!$session->user) {
            $mailbox = "";
        } else {
            # Even if client is trusted, make sure they are authenticated for $mailbox
            my $path = MailHog::Transport::Path->new->from_json($mailbox);
            if($path->mailbox ne $session->user->mailbox || $path->domain ne $session->user->domain) {
                # Don't trust them!
                $mailbox = "";
            }
        }

        # Stash the auth (may now be <> if client isn't trusted)
        $session->stash('mail_params')->{'AUTH'} = "<$mailbox>";
    } else {
        # If client is authenticated, store AUTH=<value> for it
        # TODO add configuration option
        if($session->user) {
            my $mailbox = $session->user->mailbox . '@' . $session->user->domain;
            $session->log("No auth provided, applying AUTH=<$mailbox> for MAIL command");
            $session->stash('mail_params')->{'AUTH'} = "<$mailbox>";
        }
    }

    if(my $rfc = $session->smtp->has_rfc('RFC3461')) {
        # Fall back to RFC3461 (DSN) if it exists
        return $rfc->mail($session, $data);
    }

    if(my $rfc = $session->smtp->has_rfc('RFC1870')) {
        # Fall back to RFC1870 (SIZE) if it exists
        return $rfc->mail($session, $data);
    }

    return $session->smtp->has_rfc('RFC5321')->mail($session, $data);
}

#------------------------------------------------------------------------------

sub auth {
	my ($self, $session, $data) = @_;

    if($session->user) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "Error: already authenticated");
        return;
    }

    if(!$data) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Syntax: AUTH mechanism");
        return;
    }

    my ($mechanism, $args) = $data =~ /^([\w-]+)\s?(.*)?$/;
    $session->log("Got mechanism [$mechanism] with args [$args]");

    if(!$self->mechanisms->{$mechanism}) {
        $session->log("Mechanism $mechanism not registered");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{COMMAND_PARAMETER_NOT_IMPLEMENTED}, "Error: authentication failed: no mechanism available");
        return;
    }

    $session->log("Mechanism $mechanism found, calling inital_response");
    $session->stash(rfc4954_mechanism => $mechanism);
    $session->state('AUTHENTICATE');
    $self->mechanisms->{$mechanism}->initial_response($session, $args);
}

#------------------------------------------------------------------------------

sub authenticate {
    my ($self, $session) = @_;

    my $buffer = $session->buffer;
    $buffer =~ s/\r?\n$//s;
    $session->buffer('');

    if($buffer eq '*') {
        $session->log("Client cancelled authentication with *");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Error: authentication failed: client cancelled authentication");
    }

    my $mechanism = $session->stash('rfc4954_mechanism');
    $session->log("Calling data for mechanism $mechanism");
    $self->mechanisms->{$mechanism}->data($session, $buffer);
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;