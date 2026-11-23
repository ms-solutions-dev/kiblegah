# Contributing

Thank you for helping. Bug reports, ideas and pull requests are welcome.

## Before you start

- **Bugs:** open an issue with your device, OS version, app version and the steps that lead to the problem.
- **Larger changes:** open an issue first, so we can agree on the approach before you invest time.
- **Translations:** all user-facing text lives in the string catalogs (`*.xcstrings`). Adding a language is a good first contribution.

## Contributor License Agreement

Before we can merge your first pull request, you need to sign our [Contributor License Agreement](CLA.md). You keep the copyright in your work; the agreement lets us ship your contribution in the app, including the App Store version.

A bot comments on your first pull request. Reply with the sentence it asks for, and you are done. The signature covers all your future contributions to this repository.

## Pull requests

- Keep each pull request focused on one change.
- Follow the existing code style; the project uses `swift-format` with the configuration in `.swift-format`.
- Add or update tests for behaviour you change, and make sure all package tests pass (`swift test --package-path Packages/<Name>`).
- Do not commit religious content (content packs, raw sources, fonts or audio of others). A new source goes into `tools/content/` as a download step, with its license added to [CONTENT.md](CONTENT.md).
- Religious content is sensitive: changes to texts, transliteration rules or prayer time calculation need a source, and prayer time changes need the reference tests to stay green.
- Write commit messages in English.
