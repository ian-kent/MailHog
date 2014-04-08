package MailHog::Server::SMTP::RFC2487;

=head NAME

MailHog::Server::SMTP::RFC2487- STARTTLS extension

=head2 DESCRIPTION

RFC2487 implements the STARTTLS extension in SMTP.

It allows connections to be udgraded to a TLS connection using the STARTTLS command.

=head2 CONFIGURATION

STARTTLS can be enabled using
    $config->{extensions}->{starttls}->{enabled}
This will broadcast the STARTTLS extension in the EHLO response.

STARTTLS can be required using
    $config->{extensions}->{starttls}->{require}
When enabled, only STARTTLS will be broadcast in an EHLO response and
any other commands before STARTTLS will result in a 530 response.
Note: Delivery is still permitted to local mailboxes without STARTTLS

STARTTLS can be required for all connections (including local delivery) using
    $config->{extensions}->{starttls}->{require_always}
When enabled, a STARTTLS is required before any attempt at mail delivery.
Warning: This may prevent external SMTP servers without STARTTLS support 
         from delivering messages to your local mailboxes.

=cut

use Modern::Perl;
use Moose;

use MojoX::IOLoop::Server::StartTLS;

has 'handles' => ( is => 'rw', default => sub { {} } );

#------------------------------------------------------------------------------

sub register {
	my ($self, $smtp) = @_;

	# Register this RFC
	if(!$smtp->has_rfc('RFC5321')) {
        die "MailHog::Server::SMTP::RFC2487 requires RFC5321";
    }
    $smtp->register_rfc('RFC2487', $self);

    if($smtp->config->{extensions}->{starttls}->{enabled}) {
    	# add commands/callbacks to list
        $smtp->register_command(['STARTTLS'], sub {
            my ($session, $data) = @_;
    		$self->starttls($session, $data);
    	});

        # TODO somehow replace EHLO to prevent anything other
        # than STARTTLS to be listed
        # - not sure under what circumstances

        if($smtp->config->{extensions}->{starttls}->{require}) {
            # Override RCPT to require STARTTLS for non-local recipients
            $smtp->register_command('RCPT', sub {
                my ($session, $data) = @_;
                $self->rcpt($session, $data);
            });
        };

        $smtp->register_replycode({
            STARTTLS_REQUIRED => 530,
        });

        
        if($smtp->config->{extensions}->{starttls}->{require_always}) {
            # Add a receive hook to prevent commands before a STARTTLS
            $smtp->register_hook('command', sub {
                my ($session, $cmd, $data, $result) = @_;

                $session->log("Checking command $cmd in RFC2487");

                # Don't let the command happen unless its EHLO, HELO, STARTTLS, QUIT or NOOP
                if($cmd !~ /^(STARTTLS|HELO|EHLO|QUIT|NOOP)$/ && !$session->{tls_enabled}) {
                    # Otherwise respond with a 530
                    $result->{response} = [$MailHog::Server::SMTP::ReplyCodes{STARTTLS_REQUIRED}, "must issue a STARTTLS command first"];
                    return 1;
                }

                # Let the command continue
                return 1;
            });
        }

    	# Add a list of commands to EHLO output
        $smtp->register_helo(sub {
            $self->helo(@_);
        });

        # Hook into accept to prevent a welcome message
        $smtp->register_hook('accept', sub {
        	my ($session, $settings) = @_;

        	# Find out if its a TLS stream
        	my $handle = $self->handles->{$session->stream->handle};
            my $tls_enabled = $handle ? 1 : 0;
            if($tls_enabled) {
                # It is, so dont send a welcome message and get rid of the old stream
                $settings->{send_welcome} = 0;
                $session->{tls_enabled} = 1;

                # Now we have a working TLS stream we don't need the handle
                delete $self->handles->{$handle};
            }
            $session->log("TLS enabled: %s", $tls_enabled);

        	return 1;
        });
    }
}

#------------------------------------------------------------------------------

sub helo {
    my ($self, $session) = @_;
    
    # Don't return STARTTLS if we're in a TLS connection
    return undef if $session->{tls_enabled};

    return "STARTTLS";
}

#------------------------------------------------------------------------------

sub starttls {
	my ($self, $session) = @_;

	$session->respond($MailHog::Server::SMTP::ReplyCodes{SERVICE_READY}, "Ready to start TLS");

    # Initiate a TLS connection
    # Note - Mojolicious generates a new socket and a new accept callback
    # which means we don't have to worry about doing an 'rset' on this connection
    MojoX::IOLoop::Server::StartTLS::start_tls(
        $session->server,
        $session->stream,
        undef,
        sub {
            my ($handle) = @_;
            $session->log("Socket upgraded to SSL: %s", (ref $handle));
            $self->handles->{$handle} = $handle;
        }
    )
}

#------------------------------------------------------------------------------

sub rcpt {
    my ($self, $session, $data) = @_;

    # We only end up here if enable is set

    # Unless TLS is already enabled, require STARTTLS for relay
    if(!$session->{tls_enabled}) {
        $session->log("Using RCPT from RFC2487 (STARTTLS)");

        # We need to re-check these here, otherwise we could accidentally
        # give a mailbox size error before a MAIL command
        if(!$session->stash('envelope') || !defined $session->stash('envelope')->from) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "send MAIL command first");
            return;
        }
        if(!$session->stash('envelope') || !!$session->stash('envelope')->data) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "DATA command already received");
            return;
        }

        # Unless we have a valid recipient, there's no point in checking anything
        if(my ($recipient) = $data =~ /^To:\s*<(.+)>$/i) {
            $session->log("Checking if $recipient is for local delivery");
            my ($u, $d) = $recipient =~ /(.*)@(.*)/;
            my $mailbox = $session->smtp->get_mailbox($u, $d);
            if(!$mailbox) {
                $session->log("Recipient is not for local delivery, rejecting RCPT");
                $session->respond($MailHog::Server::SMTP::ReplyCodes{STARTTLS_REQUIRED}, "must issue a STARTTLS command first");
                return;
            }
        }
    }
    
    # TODO find a cleaner way of chaining RFCs
    if(my $rfc = $session->smtp->has_rfc('RFC1870')) {
        return $rfc->rcpt($session, $data);
    }
    return $session->smtp->has_rfc('RFC5321')->rcpt($session, $data);
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;