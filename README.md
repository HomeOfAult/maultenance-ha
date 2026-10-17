# maultenance-ha

A Home Assistant custom integration for [mAultenance](https://github.com/thault/maultenance), a self-hosted household maintenance/task tracker. Polls the mAultenance API and exposes tasks in Home Assistant as a to-do list plus per-task sensors, for use in dashboards, automations, and displays.

## What it adds

- **`todo.maultenance`** — a checklist of every active task. Checking an item off marks it complete in mAultenance. Works with the built-in to-do list card and Assist voice.
- **One device per task**, each with:
  - `sensor.<task>_due_date` (`device_class: date`) — the task's current due date, with title/description/rrule/anchor mode/completion info as attributes.
  - `binary_sensor.<task>_overdue` (`device_class: problem`) — on when the task is overdue.
- Tasks are polled every 5 minutes. A task archived in mAultenance has its device and entities removed from Home Assistant on the next poll.

## Setting it up in Home Assistant

### 1. Create a Personal Access Token in mAultenance

Home Assistant authenticates as a regular mAultenance user via a token, not a shared admin login — use a dedicated account (e.g. a "Home Assistant" user created via `/settings/users`) if you want completions made from HA to be attributable separately from a person.

1. Log in to the mAultenance web UI as that user.
2. Go to **API Tokens** (`/settings/tokens`).
3. Under "Name", enter something identifiable (e.g. `Home Assistant`) and click **Create token**.
4. Copy the token immediately — it's shown once and can't be retrieved again later, only revoked.

### 2. Install the integration

**Via HACS** (recommended once this repo is public):
1. HACS → the **⋮** menu (top right) → **Custom repositories**.
2. Add this repo's URL, category **Integration**.
3. Search for "mAultenance" in HACS and install it.
4. Restart Home Assistant.

**Manually**, without HACS:
1. Copy the `custom_components/maultenance` directory from this repo into your Home Assistant config directory, so you end up with `<config>/custom_components/maultenance/`.
2. Restart Home Assistant.

### 3. Add the integration

1. Settings → **Devices & Services** → **Add Integration**.
2. Search for "mAultenance".
3. Enter:
   - **Base URL**: the full URL of your mAultenance server (e.g. `http://maultenance.local:8080`), reachable from the machine running Home Assistant.
   - **Personal Access Token**: the token from step 1.
4. Submit. If the URL or token is wrong, the form will tell you (`cannot_connect` / `invalid_auth`) rather than silently failing.

### 4. What you get

- A `todo.maultenance` entity — add it to a dashboard with the built-in **To-do List** card, or just ask Assist "what's on my mAultenance list".
- One device per active task under Settings → Devices & Services → mAultenance → *N* devices, each with a `sensor.<task>_due_date` and `binary_sensor.<task>_overdue`.
- Everything refreshes every 5 minutes. Archiving a task in mAultenance removes its device from Home Assistant on the next refresh; adding a task adds its device without needing to reload the integration.

A couple of starting points once it's set up:

```yaml
# Example automation: notify when anything becomes overdue
trigger:
  - trigger: state
    entity_id: binary_sensor.replace_furnace_filter_overdue
    to: "on"
action:
  - action: notify.mobile_app_your_phone
    data:
      message: "{{ state_attr(trigger.entity_id, 'title') }} is overdue"
```

If you'd rather not hardcode entity ids per task (they come and go as tasks are added/archived), template over every mAultenance binary sensor instead, using HA's built-in `integration_entities()`:

```yaml
{{ 'maultenance' | integration_entities
   | select('match', 'binary_sensor\.')
   | select('is_state', 'on')
   | map('state_attr', 'title')
   | list }}
```

## Development

Requires Python 3.14+ (matches current Home Assistant core).

```
python3 -m venv .venv
.venv/bin/pip install -r requirements_test.txt
.venv/bin/pytest tests/ -v
```

## Releases

Merging to `main` cuts a release automatically when the commits since the last tag are releasable Conventional Commits (`feat:` -> minor, `fix:` -> patch, breaking -> minor while in 0.y.z; `docs`/`chore`/`ci` release nothing). CI creates the `vX.Y.Z` tag and GitHub Release and attaches `maultenance.zip`, which HACS installs. The `version` in `manifest.json` is set to the release version inside that zip; the value committed in the repo is only a placeholder. To cut one by hand, run the CI workflow from the Actions tab on `main` and pick a bump.

## Status

Read/write task sync (todo list + per-task sensors) is implemented. A digest/aggregate sensor for physical displays (e-ink, receipt printer) is a planned follow-up — see open issues.
