package MailHog::Api::V1;

use Mojo::Base 'Mojolicious::Controller';

sub list {
	my $self = shift;
	$self->render_later;
	my $start = $self->req->url->query->param('s') // $self->req->url->query->param('start') // 0;
	my $limit = $self->req->url->query->param('l') // $self->req->url->query->param('limit') // 100;
	$limit = 1000 if $limit > 1000;
	$self->mango->db('mailhog')->collection('messages')->find({})->limit($limit)->skip($start)->all(sub {
		my ($mango, $error, $doc) = @_;
		$self->render(json => $doc);
	});
}

1;