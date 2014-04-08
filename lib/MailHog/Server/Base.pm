package MailHog::Server::Base;

#-------------------------------------------------------------------------------

use Modern::Perl;
use Moose;
use DateTime::Tiny;
use Mojolicious;
use Mojo::IOLoop;
use MailHog::Log;

#-------------------------------------------------------------------------------

# Events
has 'events'        => ( is => 'rw', default => sub { {} } );

# Backend
has 'backend'       => ( is => 'rw' );

# RFC/Plugin hooks
has 'commands'      => ( is => 'rw' );
has 'states'        => ( is => 'rw' );
has 'hooks'         => ( is => 'rw' );
has 'rfcs'          => ( is => 'rw' );

# Server config
has 'config'    => ( is => 'rw' );
has 'ident'     => ( is => 'rw', default => sub { 'MailHog' });

#-------------------------------------------------------------------------------

sub on {
    my ($self, $event, $callback) = @_;
    $self->events->{$event} //= [];
    push $self->events->{$event}, $callback;
    return $self;
}

#-------------------------------------------------------------------------------

sub call {
    my ($self, $event) = (shift, shift);
    my $last;
    if(my $events = $self->events->{$event}) {
        $last = $_->(@_) for @$events;
    }
    return $last;
}

#-------------------------------------------------------------------------------

sub register_command {
    my ($self, $command, $callback) = @_;
	$self->commands({}) if !$self->commands;

    $command = [$command] if ref($command) ne 'ARRAY';    
    MailHog::Log->debug("Registered callback for commands: %s", (join ', ', @$command));
    map { $self->commands->{$_} = $callback } @$command;
}

#-------------------------------------------------------------------------------

sub register_state {
    my ($self, $name, $callback) = @_;
    $self->states({}) if !$self->states;

    MailHog::Log->debug("Registered callback for state '%s'", $name);
    $self->states->{$name} = $callback;
}

#-------------------------------------------------------------------------------

sub register_hook {
    my ($self, $hook, $callback) = @_;
    $self->hooks({}) if !$self->hooks;    
    $self->hooks->{$hook} = [] if !$self->hooks->{$hook};

    MailHog::Log->debug("Registered callback for hook '%s'", $hook);
    push $self->hooks->{$hook}, $callback;
}

#-------------------------------------------------------------------------------

sub call_hook {
    my ($self, $hook, @args) = @_;
    
    my $result = 1;
    MailHog::Log->debug("Calling hook '%s'", $hook);

    if($self->hooks && $self->hooks->{$hook}) {
        for my $h (@{$self->hooks->{$hook}}) {
            my $r = &{$h}(@args);
            $result = 0 if !$r;
            last if !$result;
        }
    }

    return $result;
}

#-------------------------------------------------------------------------------

sub register_rfc {
    my ($self, $rfc, $class) = @_;
    $self->rfcs({}) if !$self->rfcs;

    my ($package) = caller;
    MailHog::Log->debug("Registered RFC '%s' with package '%s'", $rfc, $package);
    $self->rfcs->{$rfc} = $class;
}

#-------------------------------------------------------------------------------

sub unregister_rfc {
    my ($self, $rfc) = @_;
    return if !$self->rfcs;

    MailHog::Log->debug("Unregistered RFC '%s'", $rfc);
    return delete $self->rfcs->{$rfc};
}

#-------------------------------------------------------------------------------

sub has_rfc {
    my ($self, $rfc) = @_;

    return 0 if !$self->rfcs;  
    return 0 if !$self->rfcs->{$rfc};
    return $self->rfcs->{$rfc};
}

#-------------------------------------------------------------------------------

sub start {
    my ($self) = @_;

    for my $port (@{$self->config->{ports}}) {
        MailHog::Log->info("Starting %s server on port %s", ref($self), $port);

        MailHog::Log->debug("Using Mojolicious version " . $Mojolicious::VERSION);

        my $server;
        $server = Mojo::IOLoop->server({port => $port}, sub {
            $self->accept($server, @_);
        });
    }

    MailHog::Log->debug("Starting Mojo::IOLoop");
    Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

    return;
}

#-------------------------------------------------------------------------------

sub accept {
	die("Must be implemented by subclass");
}

#-------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;