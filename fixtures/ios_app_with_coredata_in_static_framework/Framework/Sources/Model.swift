import CoreData
import Foundation

public final class MyModel {
    private var persistentContainer: NSPersistentContainer = {
        let momdName = "Users"

        guard let modelURL = Bundle.module.url(forResource: momdName, withExtension: "momd") else {
            fatalError("Error loading model from bundle")
        }

        guard let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Error initializing mom from: \(modelURL)")
        }

        let container = NSPersistentContainer(name: momdName, managedObjectModel: mom)

        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    public init() {}

    public func save() {
        let context = persistentContainer.viewContext

        let user = User(context: context)

        let identifier = Int64.random(in: 0 ... 1000)
        user.name = "Foo_\(identifier)"
        user.identifier = identifier

        if context.hasChanges {
            do {
                try context.save()
            } catch {
                fatalError("Unresolved error \(error)")
            }
        }
    }

    public func load() {
        do {
            let context = persistentContainer.viewContext
            let requst: NSFetchRequest<User> = User.fetchRequest()
            let results: [User] = try context.fetch(requst)
            let descriptions = results.map {
                "- \($0.name ?? "<nil>"): \($0.identifier)"
            }
            print(descriptions.joined(separator: "\n"))
        } catch {
            fatalError("unresolved error \(error)")
        }
    }
}
