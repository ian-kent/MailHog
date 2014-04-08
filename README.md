MailHog
=======

Inspired by [MailCatcher](http://mailcatcher.me/), easier to install.

Based on [Mojolicious](http://mojolicio.us), born out of [M3MTA](https://github.com/ian-kent/M3MTA).

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

### To-do

* Add REST API for other applications and web UI
* Build web UI to interact with MailHog (potentially AngularJS/Bootstrap?)
* Add backend storage for message persistence (M3MTA backend?)

### Contributing

Fork and send a pull request!

### Licence

Copyright (C) 2014, Ian Kent (http://www.iankent.eu).

Released under MIT license, see [LICENSE](license) for details.
