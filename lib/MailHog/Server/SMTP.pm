package MailHog::Server::SMTP;

=head NAME
MailHog::Server::SMTP - Mojo::IOLoop based SMTP server
=cut

use Modern::Perl;
use Moose;
extends 'MailHog::Server::Base';

use MailHog::Server::SMTP::Session;

use MailHog::Server::SMTP::RFC5321; # Basic/Extended SMTP
use MailHog::Server::SMTP::RFC1870; # SIZE extension
use MailHog::Server::SMTP::RFC2487; # STARTTLS extension
use MailHog::Server::SMTP::RFC2920; # PIPELINING extension
use MailHog::Server::SMTP::RFC3461; # DSN extension
use MailHog::Server::SMTP::RFC4954; # AUTH extension

# TODO
# - VRFY
# - ETRN
# - EXPN
# - DSN
# - 8BITMIME
# - ENHANCEDSTATUSCODES

#------------------------------------------------------------------------------

our %ReplyCodes = ();
has 'helo' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );

#------------------------------------------------------------------------------

sub BUILD {
    my ($self) = @_;

    # Initialise RFCs
    MailHog::Server::SMTP::RFC5321->new->register($self); # Basic/Extended SMTP
    MailHog::Server::SMTP::RFC1870->new->register($self); # SIZE extension
    MailHog::Server::SMTP::RFC2487->new->register($self); # STARTTLS extension
    MailHog::Server::SMTP::RFC2920->new->register($self); # PIPELINING extension
    MailHog::Server::SMTP::RFC3461->new->register($self); # DSN extension
    MailHog::Server::SMTP::RFC4954->new->register($self); # AUTH extension
}

#------------------------------------------------------------------------------

# Handles new connections from MailHog::Server::Base
sub accept {
    my ($self, $server, $loop, $stream, $id) = @_;

    MailHog::Log->debug("Session accepted with id %s", $id);

    # 5 minutes
    # TODO timeouts from RFC5321
    $stream->timeout(300);

    MailHog::Server::SMTP::Session->new(
        smtp => $self, 
        stream => $stream,
        loop => $loop,
        id => $id,
        server => $loop->{acceptors}{$server},
    )->begin;

    return;
}

#------------------------------------------------------------------------------

# Registers an SMTP replycode
sub register_replycode {
    my ($self, $name, $code) = @_;

    if(ref($name) =~ /HASH/) {
        for my $n (keys %$name) {
            MailHog::Log->debug("Registered replycode %s => %s", $n, $name->{$n});
            $MailHog::Server::SMTP::ReplyCodes{$n} = $name->{$n};
        }
    } else {
        MailHog::Log->debug("Registered replycode %s => %s", $name, $code);
        $MailHog::Server::SMTP::ReplyCodes{$name} = $code;
    }
}

#------------------------------------------------------------------------------

# Registers an SMTP HELO response
sub register_helo {
    my ($self, $callback) = @_;
    
    MailHog::Log->debug("Registered callback for helo");

    push $self->helo, $callback;
}

#------------------------------------------------------------------------------

sub get_user {
    my ($self, $username, $password) = @_;

    # FIXME
    #return $self->backend->get_user($username, $password);
    return {};
}

#------------------------------------------------------------------------------

sub get_mailbox {
    my ($self, $mailbox, $domain) = @_;

    # FIXME
    #return $self->backend->get_mailbox($mailbox, $domain);
    return {
        size => {
            maximum => -1
        }
    };
}

#------------------------------------------------------------------------------    

sub can_user_send {
    my ($self, $session, $from) = @_;

    # FIXME
    #return $self->backend->can_user_send($session, $from);
    return 1;
}

#------------------------------------------------------------------------------

sub can_accept_mail {
    my ($self, $session, $to) = @_;

    # FIXME
    #return $self->backend->can_accept_mail($session, $to);
    return 1;
}

#------------------------------------------------------------------------------

sub queue_message {
    my ($self, $email) = @_;

    use Data::Dumper; print Dumper $email;

    #return $self->backend->queue_message($email);
    return $self->call('queue_message', $email);
}


#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;