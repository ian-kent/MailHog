MailHog
=======

Inspired by [MailCatcher](http://mailcatcher.me/), easier to install.

Based on [Mojolicious](http://mojolicio.us), born out of [M3MTA](https://github.com/ian-kent/M3MTA).

### Requirements

* A recent version of Perl (5.16+)
* [Mojolicious](http://mojolicio.us)
* [Mango](http://mojolicio.us/perldoc/Mango)

### Getting started

Start MailHog:

```./bin/mailhog daemon --listen http://*:3000```

It will attempt to listen on port 25 by default.
All SMTP server configuration is in lib/MailHog.pm.

### Licence

Copyright (C) 2014, Ian Kent (http://www.iankent.eu).

Released under MIT license, see [LICENSE](license) for details.
