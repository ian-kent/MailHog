package MailHog;

use strict;
use warnings;
use Mojo::Base 'Mojolicious';
use MailHog::Server::SMTP;
use MailHog::Server::Message;
use Mango;
use Mango::BSON 'bson_time';

sub startup {
	my $self = shift;

    # Get a Mango connection
    $self->helper(mango => sub {
    	state $mango = Mango->new('mongodb://localhost:27017');
    });

	# Start the MTA backend
	$self->helper(smtp => sub {
		state $mailhog = MailHog::Server::SMTP->new(
			config => {
			    "hostname" => "MailHog.local",
			    "ports" => [ 25 ],
			    "maximum_size" => 10240000,
			    "extensions" => {
			        "size" => {
			            "broadcast" => 1,
			            "enforce" => 1,
			            "rcpt_check" => 1
			        },
			        "starttls" => {
			            "enabled" => 1,
			            "require" => 0,
			            "require_always" => 0
			        },
			        "auth" => {
			            "mechanisms" => {
			                "PLAIN" => "MailHog::Server::SMTP::RFC4954::PLAIN",
			                "LOGIN" => "MailHog::Server::SMTP::RFC4954::LOGIN",
			                "CRAM-MD5" => "MailHog::Server::SMTP::RFC4954::CRAM_MD5"
			            },
			            "plain" => {
			                "allow_no_tls" => 0
			            }
			        }
			    },
			    "relay" => {
			        "auth" => 1,
			        "anon" => 1 
			    },
			    "commands" => {
			        "vrfy" => 0,
			        "expn" => 0
			    }
			}
		);
		return $mailhog;
	});

	$self->smtp->on(queue_message => sub {
		my ($message) = @_;
		# TODO async, caller expects return value
		my $content = MailHog::Server::Message->new->from_data($message->{data})->to_json;
		$self->mango->db('mailhog')->collection('messages')->insert({%$message, created => bson_time, content => $content});
		return "250 $message->{id} message accepted for delivery";
	});

	$self->smtp->start(1);

	my $r = $self->routes;
	$r->get('/')->to(cb => sub { shift->render('index'); });
	$r->get('/api/v1/messages')->to('api-v1#list');
	$r->post('/api/v1/messages/delete')->to('api-v1#delete');
	$r->post('/api/v1/messages/:message_id/delete')->to('api-v1#deleteOne');

	return;
}

1;