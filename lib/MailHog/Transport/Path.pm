package MailHog::Transport::Path;

use Modern::Perl;
use Moose;

use overload
	'""' => sub {
		my ($self) = @_;
		return $self->mailbox . ($self->domain ? '@' . $self->domain : '');
	};

#------------------------------------------------------------------------------

has 'relays' => ( is => 'rw', isa => 'ArrayRef', default => sub { [] } );
has 'mailbox' => ( is => 'rw', isa => 'Str' );
has 'domain' => ( is => 'rw', isa => 'Str' );

has 'params' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );

#------------------------------------------------------------------------------

sub null {
	my ($self) = @_;

	return 1 if !$self->mailbox && !$self->domain;
	return 0;
}

sub postmaster {
	my ($self) = @_;

	return 1 if $self->mailbox =~ /^postmaster$/i;
	return 0;
}

#------------------------------------------------------------------------------

sub from_text {
	my ($self, $email) = @_;

	my $relays = undef;
	my $mailbox = undef;
	my $domain = undef;
	if($email =~ /:/) {
		($relays, $email) = split /:/, $email, 2;
	}
	if($email =~ /@/) {
		($mailbox, $domain) = split /@/, $email, 2;
	} else {
		$mailbox = $email;
	}

	$self->relays(split /,/, $relays) if $relays;
	$self->mailbox($mailbox) if $mailbox;
	$self->domain($domain) if $domain;

	return $self;
}

#------------------------------------------------------------------------------

sub from_json {
	my ($self, $json) = @_;

	$self->relays($json->{relays});
	$self->mailbox($json->{mailbox});
	$self->domain($json->{domain});
	$self->params($json->{params});

	return $self;
}

#------------------------------------------------------------------------------

sub to_json {
	my ($self) = @_;

	return {
		relays => $self->relays,
		mailbox => $self->mailbox // '',
		domain => $self->domain // '',
		params => $self->params,
	};
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;
