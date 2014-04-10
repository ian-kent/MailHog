package MailHog::Api::V1;

use Mojo::Base 'Mojolicious::Controller';
use Mango::BSON 'bson_oid';

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

sub delete {
	my $self = shift;
	$self->render_later;
	$self->mango->db('mailhog')->collection('messages')->remove(sub {
		$self->render(text => '');
	});
}

sub deleteOne {
	my $self = shift;
	$self->render_later;
	$self->mango->db('mailhog')->collection('messages')->remove({ _id => bson_oid($self->stash('message_id'))}, sub {
		$self->render(text => '');
	});
}

1;