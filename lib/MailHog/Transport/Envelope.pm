package MailHog::Transport::Envelope;

use Modern::Perl;
use Moose;

#------------------------------------------------------------------------------

has 'from' => ( is => 'rw', isa => 'MailHog::Transport::Path' );
has 'to' => ( is => 'rw', isa => 'ArrayRef[MailHog::Transport::Path]', default => sub { [] } );
has 'data' => ( is => 'rw', isa => 'Str' );
has 'helo' => ( is => 'rw', isa => 'Str' );

#------------------------------------------------------------------------------

sub add_recipient {
	my ($self, $to) = @_;

	return push $self->to, MailHog::Transport::Path->new->from_json($to);
}

#------------------------------------------------------------------------------

sub remove_recipient {
	my ($self, $to) = @_;

	my @recipients = grep { $_ if $_ != $to } @{$self->to};
	return $self->to(\@recipients);
}

#------------------------------------------------------------------------------

sub from_json {
	my ($self, $json) = @_;

	$self->from($json->{from});
	for my $to (@{$json->{to}}) {
		push $self->to, MailHog::Transport::Path->new->from_json($to);
	}
	$self->data($json->{data});
	$self->helo($json->{helo});
}

#------------------------------------------------------------------------------

sub to_json {
	my ($self) = @_;

	my @to;
	for my $t (@{$self->to}) {
		push @to, $t->to_json;
	}
	return {
		from => $self->from->to_json,
		to => \@to,
		data => $self->data,
		helo => $self->helo,
	};
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;
