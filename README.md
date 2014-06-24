MailHog
=======

Inspired by [MailCatcher](http://mailcatcher.me/), easier to install.

Based on [Mojolicious](http://mojolicio.us), born out of [M3MTA](https://github.com/ian-kent/M3MTA).

** No longer under development - see [Go-MailHog](https://github.com/ian-kent/Go-MailHog) **

### Requirements

* A recent version of Perl (5.16+)
* [Mojolicious](http://mojolicio.us)
* [Mango](http://mojolicio.us/perldoc/Mango)

### Getting started

Install dependencies:

```cpanm --installdeps .```

Start MailHog:

```./bin/mailhog daemon --listen http://*:3000```

The port specified is the Mojolicious application port,
which currently does very little but will become the 
web UI to MailHog.

#### SMTP server

The SMTP server will attempt to listen on port 25
by default.

All SMTP configuration is currently in lib/MailHog.pm.

#### Development and production mode

Like any other Mojolicious application, you can start
MailHog using ```morbo``` or ```hypnotoad```.

You can also use any existing Mojolicious plugins in MailHog.

### To-do

* Refactor to use Mojo::Base instead of Moose
* Use Mojo::EventEmitter for SMTP interface
* Add REST API for other applications and web UI
* Build web UI to interact with MailHog (potentially AngularJS/Bootstrap?)
* Add backend storage for message persistence (M3MTA backend?)

### Contributing

Fork and send a pull request!

### Licence

Copyright ©‎ 2014, Ian Kent (http://www.iankent.eu).

Released under MIT license, see [LICENSE](license) for details.
