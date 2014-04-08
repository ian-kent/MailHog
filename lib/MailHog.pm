package MailHog;

use Mojo::Base 'Mojolicious';
use MailHog::Server::SMTP;

sub startup {
	my $self = shift;

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
		print "####### RECEIVED MESSAGE:\n";
		use Data::Dumper; print Dumper $message;
		return "250 $message->{id} message accepted for delivery";
	});
	$self->smtp->start;

	my $r = $self->routes;
	$r->get('/')->to(cb => sub {
		shift->render(text => 'Welcome to MailHog');
	});

	return;
}

1;