# Tuist Gradle cache for GitLab CI

Keep Gradle's dependency and wrapper caches across jobs on Tuist Linux and
macOS runners. Include the template and reference its snippet before Gradle
runs:

```yaml
include:
  - remote: https://raw.githubusercontent.com/tuist/gradle-cache-gitlab/v1/gradle-cache.yml

test:
  tags: [tuist-linux]
  before_script:
    - !reference [.tuist-gradle-cache, before_script]
  script:
    - ./gradlew test
```

The snippet attaches a cache volume at `$GRADLE_USER_HOME/caches` and
`$GRADLE_USER_HOME/wrapper` (`~/.gradle` when `GRADLE_USER_HOME` is unset). Set
`GRADLE_USER_HOME` in `variables` if you use one, and remove `cache:paths` that
restore into those directories. Use `!reference` rather than `extends`, which
replaces `before_script`. You can also vendor `gradle-cache.yml` and use
`include:local`.

Gradle cleans its cache only when its daemon stops, which a CI job rarely
reaches. The snippet installs an init script in `$GRADLE_USER_HOME/init.d` that
cleans after every build and removes entries unused for seven days.

Successful default-branch push, schedule and web pipelines save the cache. On
runners that are not Tuist runners the snippet does nothing, and if the volume
is unavailable the job runs with an empty cache; it never fails the job.
`SOURCE_COMMIT` records its monorepo source.
