Email Keywords
==============

.. role:: example-rule-emphasis

email.from
----------

Matches the MIME ``From`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.from; content:"<content to match against>";

``email.from`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.from``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``from`` with the value ``toto <toto@gmail.com>``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email from"; :example-rule-emphasis:`email.from; content:"toto <toto@gmail.com>";` sid:1;)

email.subject
-------------

Matches the MIME ``Subject`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.subject; content:"<content to match against>";

``email.subject`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.subject``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``subject`` with the value ``This is a test email``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email subject"; :example-rule-emphasis:`email.subject; content:"This is a test email";` sid:1;)

email.to
--------

Matches the MIME ``To`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.to; content:"<content to match against>";

``email.to`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.to``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``to`` with the value ``172.16.92.2@linuxbox``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email to"; :example-rule-emphasis:`email.to; content:"172.16.92.2@linuxbox";` sid:1;)

email.cc
--------

Matches the MIME ``Cc`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.cc; content:"<content to match against>";

``email.cc`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.cc[]``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``cc`` with the value ``Emily <emily.roberts@example.com>, Ava <ava.johnson@example.com>, Sophia Wilson <sophia.wilson@example.com>``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email cc"; :example-rule-emphasis:`email.cc; content:"Emily <emily.roberts@example.com>, Ava <ava.johnson@example.com>, Sophia Wilson <sophia.wilson@example.com>";` sid:1;)

email.date
----------

Matches the MIME ``Date`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.date; content:"<content to match against>";

``email.date`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.date``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``date`` with the value ``Fri, 21 Apr 2023 05:10:36 +0000``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email date"; :example-rule-emphasis:`email.date; content:"Fri, 21 Apr 2023 05:10:36 +0000";` sid:1;)

email.message_id
----------------

Matches the MIME ``Message-Id`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.message_id; content:"<content to match against>";

``email.message_id`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.message_id``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``message id`` with the value ``<alpine.DEB.2.00.1311261630120.9535@sd-26634.dedibox.fr>``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email message id"; :example-rule-emphasis:`email.message_id; content:"<alpine.DEB.2.00.1311261630120.9535@sd-26634.dedibox.fr>";` sid:1;)

email.x_mailer
--------------

Matches the MIME ``X-Mailer`` field of an email.

Comparison is case-sensitive.

Syntax::

 email.x_mailer; content:"<content to match against>";

``email.x_mailer`` is a 'sticky buffer' and can be used as a ``fast_pattern``.

This keyword maps to the EVE field ``email.x_mailer``

Example
^^^^^^^

Example of a signature that would alert if a packet contains the MIME field ``x-mailer`` with the value ``Microsoft Office Outlook, Build 11.0.5510``

.. container:: example-rule

  alert smtp any any -> any any (msg:"Test mime email x-mailer"; :example-rule-emphasis:`email.x_mailer; content:"Microsoft Office Outlook, Build 11.0.5510";` sid:1;)
