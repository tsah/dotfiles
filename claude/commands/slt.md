---
description: Annotate this workshop's Linear ticket in Schlop (Neovim) and send the annotations to Claude
argument-hint: "[TWE-1234]"
disable-model-invocation: true
---

The user just annotated the Linear ticket for this work in Schlop. The ticket and their annotations are attached to this message as UserPromptSubmit hook context. Treat that feedback as the user's message about the ticket and respond to it. Do not change the ticket in Linear unless they ask.

If no Schlop feedback is attached, the Schlop plugin hook did not run: say so and do nothing else.
