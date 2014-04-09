package MailHog::Server::Message;

use Modern::Perl;
use Moose;

has 'headers' => ( is => 'rw', isa => 'HashRef', default => sub { {} } );
has 'body'    => ( is => 'rw', isa => 'Str' );
has 'size'	  => ( is => 'rw', isa => 'Int' );

#------------------------------------------------------------------------------

sub from_json {
	my ($self, $json) = @_;

	$self->headers($json->{headers});
	$self->body($json->{body});
	$self->size($json->{size});

	return $self;
}

#------------------------------------------------------------------------------

sub to_json {
	my ($self) = @_;

	return {
		headers => $self->headers,
		body => $self->body,
		size => $self->size,
	};
}

#------------------------------------------------------------------------------

sub from_data {
	my ($self, $data) = @_;

	# Extract headers and body
    my ($headers, $body) = split /\r\n\r\n/m, $data, 2;

    # Parse the headers
    my @hdrs = split /\r\n/m, $headers;
    my %h = ();
    my $lasthdr = undef;
    for my $hdr (@hdrs) {
        if($lasthdr && $hdr =~ /^[\t\s]/) {
            # We've got a multiline header
            my $hx = $h{$lasthdr};
            if(ref($hx) eq 'ARRAY') {
                $hx->[-1] .= "\r\n$hdr";
            } else {
                $h{$lasthdr} .= "\r\n$hdr";
            }
            next;
        }

        my ($key, $value) = split /:\s/, $hdr, 2;
        $lasthdr = $key;

        if($h{$key}) {
            $h{$key} = [$h{$key}] if ref($h{$key}) !~ /ARRAY/;
            push $h{$key}, $value;
        } else {
            $h{$key} = $value;
        }
    }

    # Store everything
    $self->headers(\%h);
    $self->body($body);

    # Store the length
    $self->size(length $data);

	return $self;
}

#------------------------------------------------------------------------------

sub to_data {
	my ($self) = @_;

	my $data = '';

	for my $header (keys %{$self->headers}) {
		if(ref($self->headers->{$header})) {
			for my $item (@{$self->headers->{$header}}) {
				$data .= $header . ": " . $item . "\r\n";
			}
		} else {
			$data .= $header . ": " . $self->headers->{$header} . "\r\n";
		}
	}
	$data .= "\r\n" if $data;

	$data .= $self->body;

	return $data;
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;