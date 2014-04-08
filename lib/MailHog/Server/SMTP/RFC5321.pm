package MailHog::Server::SMTP::RFC5321;

use Modern::Perl;
use Moose;

use MailHog::Transport::Path;
use MailHog::Transport::Envelope;

use Data::Uniqid qw/ luniqid /;
use Date::Format;

#------------------------------------------------------------------------------

sub register {
	my ($self, $smtp) = @_;

	# Register this RFC
    $smtp->register_rfc('RFC5321', $self);

	# Add some reply codes
	$smtp->register_replycode({
		SYSTEM_MESSAGE								=> 211,
		HELP_MESSAGE								=> 214,

	    SERVICE_READY                               => 220,
	    SERVICE_CLOSING_TRANSMISSION_CHANNEL        => 221,

	    REQUESTED_MAIL_ACTION_OK                    => 250,
	    USER_NOT_LOCAL_WILL_FORWARD					=> 251,
	    ARGUMENT_NOT_CHECKED                        => 252,

	    START_MAIL_INPUT                            => 354,

	    SERVICE_NOT_AVAILABLE						=> 421,

	    MAILBOX_UNAVAILABLE							=> 450,
	    ERROR_IN_PROCESSING							=> 451,
	    INSUFFICIENT_SYSTEM_STORAGE					=> 452,

        UNABLE_TO_ACCOMODATE_PARAMETERS             => 455,

		COMMAND_NOT_UNDERSTOOD                      => 500,
		SYNTAX_ERROR_IN_PARAMETERS                  => 501,
		COMMAND_NOT_IMPLEMENTED                     => 502,
	    BAD_SEQUENCE_OF_COMMANDS                    => 503,	
	    COMMAND_PARAMETER_NOT_IMPLEMENTED			=> 504,

	    REQUESTED_ACTION_NOT_TAKEN					=> 550,	
	    USER_NOT_LOCAL_PLEASE_TRY					=> 551,
	    EXCEEDED_STORAGE_ALLOCATION					=> 552,
	    MAILBOX_NAME_NOT_ALLOWED					=> 553,
	    TRANSACTION_FAILED							=> 554,
        MAIL_FROM_TO_PARAMETERS_NOT_RECOGNISED      => 555,
	});

	# Add a receive hook to prevent commands before a HELO
	$smtp->register_hook('command', sub {
		my ($session, $cmd, $data, $result) = @_;

        $session->log("Checking command $cmd in RFC5321");

		# Don't let the command happen unless its HELO, EHLO, QUIT, NOOP or RSET
		if($cmd !~ /^(HELO|EHLO|RSET|QUIT|NOOP|HELP|EXPN|VRFY)$/ && !$session->stash('helo')) {
            $result->{response} = [$MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "bad sequence of commands"];
            return 1;
	    }

        # Create new param stores
        if($cmd eq 'MAIL') {
            $session->stash('mail_params' => {});
        } elsif ($cmd eq 'RCPT') {
            $session->stash('rcpt_params' => {});
        }

	    # Let the command continue
        return 1;
	});

	# Add the commands
    $smtp->register_command('HELO', sub {
        my ($session, $data) = @_;
        $self->helo($session, $data);
    });

    $smtp->register_command('EHLO', sub {
        my ($session, $data) = @_;
        $self->ehlo($session, $data);
    });

    $smtp->register_command('TURN', sub {
        my ($session, $data) = @_;
        $self->turn($session, $data);
    });

	$smtp->register_command('MAIL', sub {
		my ($session, $data) = @_;
		$self->mail($session, $data);
	});

	$smtp->register_command('RCPT', sub {
		my ($session, $data) = @_;
		$self->rcpt($session, $data);
	});

	$smtp->register_command('DATA', sub {
		my ($session, $data) = @_;
		$self->data($session, $data);
	});

	# Register a state hook to capture data
	$smtp->register_state('DATA', sub {
		my ($session) = @_;
		$self->data($session);
	});

	$smtp->register_command('RSET', sub {
        my ($session, $data) = @_;
        $self->rset($session, $data);
    });

    if(!exists $smtp->config->{commands}->{vrfy} || $smtp->config->{commands}->{vrfy}) {
        $smtp->register_command('VRFY', sub {
            my ($session, $data) = @_;
            $self->vrfy($session, $data);
        });
        $smtp->register_helo(sub {
            return "VRFY";
        });
    }

    if(!exists $smtp->config->{commands}->{expn} || $smtp->config->{commands}->{expn}) {
        $smtp->register_command('EXPN', sub {
            my ($session, $data) = @_;
            $self->expn($session, $data);
        });
        $smtp->register_helo(sub {
            return "EXPN";
        });
    }

	$smtp->register_command('NOOP', sub {
		my ($session, $data) = @_;
		$self->noop($session, $data);
	});

	$smtp->register_command('QUIT', sub {
		my ($session, $data) = @_;
		$self->quit($session, $data);
	});

	$smtp->register_command('HELP', sub {
		my ($session, $data) = @_;
		$self->help($session, $data);
	});
}

#------------------------------------------------------------------------------

sub helo {
	my ($self, $session, $data) = @_;

	if(!$data || $data =~ /^\s*$/) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "you didn't introduce yourself");
        return;
    }

    $session->stash(helo => $data);
    $session->stash(extended => 0);

    $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK} . " Hello '$data'. I'm", $session->smtp->ident);
}

#------------------------------------------------------------------------------

sub ehlo {
    my ($self, $session, $data) = @_;

    if(!$data || $data =~ /^\s*$/) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "you didn't introduce yourself");
        return;
    }

    $session->stash(helo => $data);
    $session->stash(extended => 1);

    # Everything except last line has - between status and message

    my @helos = ();
    for (my $i = 0; $i < scalar @{$session->smtp->helo}; $i++) {
        my $helo = &{$session->smtp->helo->[$i]}($session);
        push @helos, $helo if $helo;
    }

    $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}.((scalar @helos == 0) ? ' ' : '-')."Hello '$data'. I'm", $session->smtp->ident);
    for (my $i = 0; $i < scalar @helos; $i++) {
        my $helo = $helos[$i];
        if($i == (scalar @helos) - 1) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}, $helo);
        } else {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK} . "-" . $helo);
        }
    }
}

#------------------------------------------------------------------------------

sub mail {
	my ($self, $session, $data) = @_;

	if($session->stash('envelope') && defined $session->stash('envelope')->from) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "MAIL command already received");
        return;
    }

    # Start a new transaction
    delete $session->stash->{data};
    $session->stash(envelope => MailHog::Transport::Envelope->new);

    if(my ($from, $params) = $data =~ /^From:<([^>]+@[^>]+)*>(.*)$/i) {
        if($params) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Unexpected parameters on MAIL command");
            return;
        }

        my $path = MailHog::Transport::Path->new->from_text($from);
        for my $param (keys %{$session->stash('mail_params')}) {
            $path->params->{$param} = $session->stash('mail_params')->{$param};
        }
        $session->stash('envelope')->from($path);

        if($path->null) {
            MailHog::Log->debug("Message has null reverse-path");
        } 

        $session->log("Checking user against '$path'");
        my $r = $session->smtp->can_user_send($session, $path);

        if(!$r) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_ACTION_NOT_TAKEN}, "Not permitted to send from this address");
            return;
        }
        $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}, ($path ? ($path . ' ') : '') . "sender ok");
        return;
    }
    $session->respond($MailHog::Server::SMTP::ReplyCodes{SYNTAX_ERROR_IN_PARAMETERS}, "Invalid sender");
}

#------------------------------------------------------------------------------

sub rcpt {
	my ($self, $session, $data) = @_;

	if(!defined $session->stash('envelope')->from) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "send MAIL command first");
        return;
    }
    if($session->stash('envelope')->data) {
        $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "DATA command already received");
        return;
    }

    if(my ($recipient, $pm) = $data =~ /^To:\s*<(?:(.+@.+)|(postmaster))>$/i) {
        $recipient ||= $pm;
        my $path = MailHog::Transport::Path->new->from_text($recipient);
        for my $param (keys %{$session->stash('rcpt_params')}) {
            $path->params->{$param} = $session->stash('rcpt_params')->{$param};
        }
        MailHog::Log->debug("Checking delivery for $path");

        if($path->postmaster) {
            MailHog::Log->debug("Auto-accepting, address is reserved postmaster");
        } else {
            my $r = $session->smtp->can_accept_mail($session, $path);

            if($r == $MailHog::Server::Backend::SMTP::REJECTED) {
                MailHog::Log->debug("Delivery rejected");
                $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_ACTION_NOT_TAKEN}, "Not permitted to send to this address");
                return;
            }
            
            if($r == $MailHog::Server::Backend::SMTP::REJECTED_LOCAL_USER_INVALID) {
                # local delivery domain but no user
                MailHog::Log->debug("Local delivery but user not found");
                $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_ACTION_NOT_TAKEN}, "Invalid recipient");
                return;
            }

            if($r == $MailHog::Server::Backend::SMTP::REJECTED_OVER_LIMIT) {
            	# mailbox is over size
                MailHog::Log->debug("Local delivery but user is over limit");
            	$session->respond($MailHog::Server::SMTP::ReplyCodes{INSUFFICIENT_SYSTEM_STORAGE}, "Mailbox exceeds maximum size");
            	return;
            }
        }

        push @{$session->stash('envelope')->to}, $path;
        MailHog::Log->debug("Delivery accepted");
        $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}, "$recipient recipient ok");
        return;
    }

    MailHog::Log->debug("Invalid recipient: $data");
    $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_ACTION_NOT_TAKEN}, "Invalid recipient");
}

#------------------------------------------------------------------------------

sub data {
	my ($self, $session, $data) = @_;

	if($session->state ne 'DATA') {
		# Called from DATA command
        if(!$session->stash('envelope') || !defined $session->stash('envelope')->from) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "send MAIL command first");
            return;
        }
		if(scalar @{$session->stash('envelope')->to} == 0) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "send RCPT command first");
            return;
        }

        if($session->stash('envelope')->data) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{BAD_SEQUENCE_OF_COMMANDS}, "DATA command already received");
            return;
        }

        $session->respond($MailHog::Server::SMTP::ReplyCodes{START_MAIL_INPUT}, "Send mail, end with \".\" on line by itself");
        $session->stash(data => '');
        $session->state('DATA');
        return;
	}

	# Called again after DATA command
    $session->stash->{'data'} .= $session->buffer;
    $session->buffer('');

	if($session->stash('data') =~ /.*\r\n\.\r\n$/s) {
        my $data = $session->stash('data');
        $data =~ s/\r\n\.\r\n$//s;

        # check total size of data against global maximum message size
        # this is an rfc0821 thing, nothing to do with SIZE
        if(length $data > $session->smtp->config->{maximum_size}) {
            $session->respond($MailHog::Server::SMTP::ReplyCodes{TRANSACTION_FAILED}, "Message exceeded maximums size");
            $session->state('ERROR');
            return;
        }

        # rfc0821 4.5.2 transparency
        $data =~ s/\n\.\./\n\./s;

        # Get or create the message id
        my $message_id;
        if(my ($msg_id) = $data =~ /message-id: <(.*)>/mi) {
            $message_id = $msg_id;
        } else {
        	# Generate a new one
        	my $id = luniqid . "@" . $session->smtp->config->{hostname};
            $message_id = $id;
        	$data = "Message-ID: $id\r\n$data";
        }
 
        # Add the return path
        my $newdata .= "Return-Path: <" . $session->stash('envelope')->from . ">\r\n";

        # Add the received header
        my $now = time2str("%d %b %y %H:%M:%S %Z", time);
        $newdata .= "Received: from " . $session->stash('helo') . " by " . $session->smtp->config->{hostname} . " (" . $session->smtp->ident . ")\r\n";
        # TODO some way to add 'with ESMTP' from RFC1869
        # TODO add in the 'for whoever' bit?
        #$newdata .= "          id " . $session->email->id . " for " . $session->email->to . "; " . $now . "\r\n";
        $newdata .= "          id $message_id ; $now\r\n";

        # Store the data
        $session->stash('envelope')->data($newdata . $data);
        $session->stash('envelope')->helo($session->stash('helo'));

        my $email = $session->stash('envelope')->to_json;
        $email->{id} = $message_id;
        $session->respond($session->smtp->queue_message($email) // ("451", "$message_id message store failed, please retry later"));

        $session->state('FINISHED');
        $session->buffer('');
    }
}

#------------------------------------------------------------------------------

sub noop {
	my ($self, $session, $data) = @_;

	$session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}, "Ok.");
}

#------------------------------------------------------------------------------

sub help {
	my ($self, $session, $data) = @_;

	$session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}, "Ok.");
}

#------------------------------------------------------------------------------

sub quit {
	my ($self, $session, $data) = @_;

	$session->respond($MailHog::Server::SMTP::ReplyCodes{SERVICE_CLOSING_TRANSMISSION_CHANNEL}, "Bye.");

    $session->stream->on(drain => sub {
        $session->stream->close;
    });
}

#------------------------------------------------------------------------------

sub rset {
    my ($self, $session, $data) = @_;

    $session->buffer('');
    $session->_stash({
        helo => $session->stash('helo')
    });
    $session->state('ACCEPT');

    $session->respond($MailHog::Server::SMTP::ReplyCodes{REQUESTED_MAIL_ACTION_OK}, "Ok.");
}

#------------------------------------------------------------------------------

sub vrfy {
    my ($self, $session, $data) = @_;

    # TODO implement properly, with config to switch on (default off)

    $session->respond($MailHog::Server::SMTP::ReplyCodes{ARGUMENT_NOT_CHECKED}, "Argument not checked.");
}

#------------------------------------------------------------------------------

sub expn {
    my ($self, $session, $data) = @_;

    # TODO implement properly, with config to switch on (default off)

    $session->respond($MailHog::Server::SMTP::ReplyCodes{ARGUMENT_NOT_CHECKED}, "Argument not checked.");
}

#------------------------------------------------------------------------------

sub send {
	my ($self, $session, $data) = @_;

    $session->respond($MailHog::Server::SMTP::ReplyCodes{COMMAND_NOT_IMPLEMENTED} . " Command not implemented");
}

#------------------------------------------------------------------------------

sub soml {
	my ($self, $session, $data) = @_;

    $session->respond($MailHog::Server::SMTP::ReplyCodes{COMMAND_NOT_IMPLEMENTED} . " Command not implemented");
}

#------------------------------------------------------------------------------

sub saml {
	my ($self, $session, $data) = @_;

    $session->respond($MailHog::Server::SMTP::ReplyCodes{COMMAND_NOT_IMPLEMENTED} . " Command not implemented");
}

#------------------------------------------------------------------------------

sub turn {
	my ($self, $session, $data) = @_;

    $session->respond($MailHog::Server::SMTP::ReplyCodes{COMMAND_NOT_IMPLEMENTED} . " Command not implemented");
}

#------------------------------------------------------------------------------

__PACKAGE__->meta->make_immutable;