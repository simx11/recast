# Agent guidelines

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/) for every commit message and pull request title:

```
<type>(<optional scope>): <description>

<optional body>

<optional footer>
```

- **Types:** `feat` (new behavior), `fix` (bug fix), `docs` (README and other docs), `refactor` (no change in behavior), `test`, `build` (Package.swift, scripts, Makefile), `ci`, `chore`.
- **Description:** imperative, lowercase, no trailing period, e.g. `feat: read SVG images by rendering them with WebKit`.
- **Scope** is optional. Use it when it helps, e.g. `fix(intake): …` or `feat(settings): …`.
- **Breaking changes:** add `!` after the type (`feat!: …`) and a `BREAKING CHANGE:` footer explaining what changed.
- Explain *why* in the body when the description alone doesn't.
