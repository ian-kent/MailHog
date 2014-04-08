package MailHog::Server::SMTP::RFC2920;

=head NAME

MailHog::Server::SMTP::RFC1870 - PIPELINING extension

=head2 DESCRIPTION

RFC1870 implements the PIPELINING extension in SMTP.

It advertises the PIPELINING extension in the SMTP EHLO response,
but adds no additional functionality - MailHog natively supports pipelining.

=cut

use Modern::Perl;
use Moose;

has 'helo' => ( is => 'rw', isa => 'Str' );

#------------------------------------------------------------------------------

sub register {
	my ($self, $smtp) = @_;

	# Register this RFC
    if(!$smtp->has_rfc('RFC5321')) {
        die "MailHog::Server::SMTP::RFC2920 requires RFC5321";
    }
    $smtp->register_rfc('RFC2920', $self);

	# Add a list of commands to EHLO output
    $smtp->register_helo(sub {
        my ($session) = @_;
        return $self->helo;
    });

    $self->helo('PIPELINING');
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;