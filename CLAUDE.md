# DropZone — Project Guidelines

## 开发规范 / Development Workflow

### Branch Management

**Main branch is protected.** Do not commit feature code, design documents, or any development work directly to `main`. The `main` branch only receives merges from verified feature/plan branches.

### Branch Naming Convention

Every plan or task must be developed on a dedicated branch:

```
plan-{number}-{short-description}
```

Examples:
- `plan-1-project-setup`
- `plan-2-notch-detection`
- `plan-3-drag-drop-shelf`
- `plan-4-ui-animations`

Hotfix branches follow: `hotfix-{number}-{short-description}`

### Workflow Steps

1. **Create branch** — Branch off from `main` with the correct naming convention.
2. **Develop** — Implement the plan on the feature branch. Commit early and often with clear messages.
3. **Test** — All tests must pass before merging. Run the full test suite.
4. **Review** — Verify the implementation matches the plan requirements.
5. **Merge** — Merge the feature branch into `main` (no fast-forward: `git merge --no-ff`).
6. **Clean up** — Delete the feature branch after a successful merge.

### Merge Checklist

Before merging any branch into `main`, confirm:

- [ ] All existing tests pass (`xcodebuild test`)
- [ ] New functionality has corresponding tests
- [ ] No compiler warnings introduced
- [ ] Code builds successfully in both Debug and Release
- [ ] Commit messages are clear and descriptive
- [ ] Branch is up to date with `main` (rebase or merge main into branch first)

### Version Tagging

Follow **Semantic Versioning** (`major.minor.patch`):

- **major** — Breaking changes or major milestones
- **minor** — New features, backward-compatible
- **patch** — Bug fixes, minor improvements

Tag format: `v0.1.0`, `v0.2.0`, `v1.0.0`

Tags are only applied on the `main` branch after a successful merge.

### Commit Message Convention

```
type: short description

Optional longer description.
```

Types: `feat`, `fix`, `refactor`, `test`, `docs`, `chore`, `style`, `build`
