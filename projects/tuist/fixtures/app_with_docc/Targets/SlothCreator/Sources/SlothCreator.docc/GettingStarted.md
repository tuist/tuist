# Getting Started with Sloths

Create a sloth and assign personality traits and abilities.

## Overview

Sloths are complex creatures that require careful creation and a suitable habitat. After creating a sloth, you're responsible for feeding them, providing fulfilling activities, and giving them opportunities to exercise and rest. 

Every sloth has a ``Sloth/name`` and ``Sloth/color-swift.property``. You can optionally provide a ``Sloth/power-swift.property`` if your sloth has special supernatural abilities.

![A diagram with the five sloth power types: ice, fire, wind, lightning, and none.](slothPower.png)

### Create a Sloth

To create a standard sloth without any special supernatural powers, you initialize a new instance of the ``Sloth`` structure, and supply a name and a color, as the following code shows:

```swift
var sloth = Sloth(name: "Super Sloth", color: .blue, power: .none)
```

If your sloth possesses one of the special powers of `ice`, `fire`, `wind`, or `lightning`, you can specify this at creation:

```swift
var superSloth = Sloth(name: "Silly Sloth", color: .green, power: .lightning)
```

If you're creating a large number of sloths, you can define your own random name generator that conforms to the ``NameGenerator`` protocol, and use it to generate names:

```swift
let slothNamer = MyCustomSlothNamer()
var sloths: [Sloth] = []

for _ in 0...100 {
    let name = slothNamer.generateName(seed: 0)
    var sloth = Sloth(name: name, color: .green, power: .ice)
    
    sloths.append(sloth)
}
```

### Provide a Habitat

Sloths thrive in comfortable habitats. To create a sloth-friendly habitat, you specify whether it's humid, warm, or both. The following listing creates a habitat that's humid and warm, which results in a high ``Habitat/comfortLevel``:

```swift
let lovelyHabitat = Habitat(isHumid: true, isWarm: true)
```

After you create a sloth habitat, you're ready for sloths to sleep in it. Sleeping in a habitat increases the ``Sloth/energyLevel`` of the sloth by the comfort level of the habitat. Sloths sleep for long periods so, by default, your sloth sleeps for 12 hours, but you can also customize this value:

```swift
superSloth.sleep(in: lovelyHabitat)
hyperSloth.sleep(in: lovelyHabitat, for: 2)
```

### Exercise a Sloth

To keep your sloths happy and fulfilled, you can create activities for them to perform. Define your activities by conforming to the ``Activity`` protocol and implementing the ``Activity/perform(with:)`` method:

```swift
struct Sightseeing: Activity {
    func perform(with sloth: inout Sloth) -> Speed {
        sloth.energyLevel -= 10
        return .slow
    }
}
```

### Feed a Sloth

Sloths require sustenance to perform activities, so you can feed them ``Sloth/Food``. Standard sloth food includes leaves and twigs:

```swift
superSloth.eat(.largeLeaf)
hyperSloth.eat(.twig)
```

### Schedule Care for a Sloth

To make it easy to care for your sloth, SlothCreator provides a ``CareSchedule`` structure that lets you define activities or foods for your sloth to enjoy at specific times. Create the schedule, then provide a tuple of a `Date` and an ``Activity``, or you can use some of the standard care procedures:

```swift
let events: [(Date, CareSchedule.Event)] = [
    (Date.now, .bedtime),
    (Date(timeIntervalSinceNow: 12*60*60), .breakfast),
    (Date(timeIntervalSinceNow: 13*60*60), .activity(Sightseeing()))
]

let schedule = CareSchedule(events: events)
superSloth.schedule = schedule
```
