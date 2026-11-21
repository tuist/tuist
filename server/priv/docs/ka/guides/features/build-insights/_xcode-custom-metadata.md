## მორგებული მეტამონაცემები {#custom-metadata}

ფილტრაციის გასაუმჯობესებლად შეგიძლიათ ბილდებს გარემოს ცვლადებით მეტამონაცემები მიამაგროთ.

### გარემოს ცვლადები

| ცვლადი | ფორმატი | აღწერა |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | მძიმით გამოყოფილი | ერთ ცვლადში რამდენიმე ტეგი. |
| `TUIST_BUILD_VALUE_*` | ერთი მნიშვნელობა | გასაღები-მნიშვნელობის წყვილი, სადაც სუფიქსი არის გასაღები. |

### მაგალითები

ბილდის გამოძახებამდე დააყენეთ ეს მნიშვნელობები CI-ში ან თქვენს shell-ში:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
