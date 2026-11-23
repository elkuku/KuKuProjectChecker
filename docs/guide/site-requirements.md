# Site requirements

The app reads the versions of a site from `https://<site>/system/info/`. The answer is JSON:

```json
{"sf_version": "8.1.11", "php_version": "8.5.12"}
```

A site can also tell its database and its last deploy (KuKu system tools bundle 1.7 or newer):

```json
{
  "sf_version": "8.1.11",
  "php_version": "8.5.12",
  "db_platform": "mariadb",
  "db_version": "12.3.4-MariaDB-deb12",
  "last_deploy": {"at": "2026-11-23T15:45:02+00:00", "status": "ok"}
}
```

A site without this endpoint, or one that doesn't answer, shows **Not reachable**.

## With the KuKu system tools bundle

The [KuKu system tools bundle](https://github.com/elkuku/SFSystemToolsBundle) provides the endpoint
for Symfony projects:

```bash
composer require elkuku/kuku-sf-system-tools-bundle
```

`config/routes/kuku_sfsysteminfo.yaml`:

```yaml
_kuku_sfsysinfo:
  resource: '@KuKuSFSystemToolsBundle/config/routes.yaml'
  prefix: /system/info
```

The versions are hidden (`N/A`) until you expose them in `config/packages/kuku_sfsysteminfo.yaml`:

```yaml
kuku_sf_system_tools:
  expose_sf_version: true
  expose_php_version: true
  expose_db_version: true    # the database badge, needs Doctrine
  expose_last_deploy: true   # the last deploy badge, from the deploy log
```

::: warning The endpoint is public
Anyone can read `/system/info/`, so only expose what you are fine with anyone seeing.
:::

::: tip
The bundle also has an About page and a deploy log viewer for admins, see its
[README](https://github.com/elkuku/SFSystemToolsBundle#readme).
:::
