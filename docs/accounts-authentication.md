# Account authentication

Loophole does not require an IDE account. Authentication dialogs are normally initiated by an extension.

## GitHub

Some GitHub extensions use a GitHub personal access token instead of the built-in Visual Studio authentication flow. Follow GitHub's current documentation when creating a token and grant only the permissions required by the extension.

## Microsoft

Extensions that use Microsoft authentication depend on the authentication implementation and services bundled by the extension. Their availability can change independently of Loophole.

## Troubleshooting

If an extension requests credentials unexpectedly:

1. Verify that the extension is installed and enabled.
2. Review the extension's permissions and authentication documentation.
3. Check the extension-host log for the failed provider or redirect URI.
4. Avoid entering credentials into unofficial prompts.

Loophole's AI requests are sent directly from the user's machine to the provider selected by the user; IDE account credentials are not required for local AI requests.
