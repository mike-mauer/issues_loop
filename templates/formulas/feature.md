# Formula: Feature

**Topology:** schema → logic → UI → integration

Use this formula when the issue describes new functionality, a new capability, or an addition to the system.

---

## Default Task Phases

### Phase 1: Schema

Define the data structures, configurations, and interfaces the feature requires.

**Typical tasks:**
- Add database schema/migration
- Create TypeScript types or interfaces
- Update configuration files
- Define API contracts

**Acceptance criteria patterns:**
- `{schema file} contains {model/type/table} definition`
- `migration creates {table} with columns: {list}`
- `npm run typecheck passes`
- `config file contains new {setting} field`

**Verify command patterns:**
```bash
npm run typecheck
npm run db:migrate
test -f {schema file} && echo "Schema exists"
grep -q "{type name}" {types file}
```

### Phase 2: Logic

Implement the core business logic, API endpoints, or backend processing.

**Typical tasks:**
- Create API endpoint(s)
- Implement service/utility functions
- Add middleware or hooks
- Write unit tests for the logic

**Acceptance criteria patterns:**
- `{endpoint} returns {status code} with valid payload`
- `{function} handles {input} and returns {output}`
- `unit tests pass for {module}`
- `npm run test passes`

**Verify command patterns:**
```bash
npm run test -- --grep "{module name}"
npm run typecheck
curl -s -o /dev/null -w '%{http_code}' {endpoint}
```

### Phase 3: UI

Build the user-facing components, pages, or visual elements.

**Typical tasks:**
- Create React/Vue/Svelte component(s)
- Add page routing
- Implement form handling and validation
- Style with CSS/Tailwind

**Acceptance criteria patterns:**
- `component file exists at {path}`
- `component renders without errors`
- `npm run build succeeds`
- `route {path} is accessible`
- `verify in browser using dev-browser skill`

**Verify command patterns:**
```bash
npm run build
npm run typecheck
test -f {component path} && echo "Component exists"
npm run test -- --grep "{component name}"
__BROWSER_VERIFY_REQUIRED__
```

### Phase 4: Integration

Wire everything together and verify end-to-end behavior.

**Typical tasks:**
- Connect UI to API endpoints
- Add error handling across boundaries
- Write integration/e2e tests
- Update documentation

**Acceptance criteria patterns:**
- `end-to-end flow works: {user action} → {expected result}`
- `error states handled: {scenario} → {user-visible message}`
- `npm run test passes (including integration tests)`
- `npm run build succeeds`

**Verify command patterns:**
```bash
npm run test
npm run build
npm run typecheck
npm run e2e  # if available
```

---

## When to Use

**Keywords in issue text:** add, create, implement, new, feature, support, enable, introduce, build
**Labels:** `feature`, `enhancement`, `new`

**Default formula:** When the issue type is ambiguous, default to `feature`.

## Task Sizing Guidance

Features vary widely. Use this guide to estimate task count:

| Scope | Phases Used | Tasks |
|-------|-------------|-------|
| Config-only feature | schema | 1-2 |
| Backend-only feature | schema → logic | 2-4 |
| Full-stack feature | schema → logic → UI → integration | 4-8 |
| Large feature | Split into sub-features, each 4-8 tasks | 8+ |

If a feature requires more than 8 tasks, consider splitting into multiple issues.
