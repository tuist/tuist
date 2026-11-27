### შეადარეთ {#tune}

მცირე რენდერინგის განსხვავებების, როგორიცაა ანტი-ალიასინგი, დასაშვებად, მიანიჭეთ პრევიუს დიფის ზღვარი: პიქსელების წილი 0-დან 1-მდე, რომლებიც შეიძლება განსხვავდებოდეს სანამ გამოსახულება ჩაითვლება შეცვლილად.

```swift
import TuistSnapshots

#Preview {
    ProfileView()
        .snapshotDiffThreshold(0.02)
}
```

პრევიუების გამოსატოვებლად, გადაწერეთ `includes(_:)` თქვენს `PreviewSnapshotTestCase` ქვეკლასში.

### პარამეტრები {#options}

- `--no-snapshots` (`TUIST_TEST_SNAPSHOTS=false`): გამორთავს ატვირთვებს CI-ში.
- `--snapshot-set <name>` (`TUIST_TEST_SNAPSHOT_SET`): ნაკრები, რომელსაც ეკუთვნის გამოსახულებები. ნაგულისხმევად არის სქემა.
