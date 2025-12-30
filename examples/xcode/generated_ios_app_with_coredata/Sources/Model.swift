import CoreData
import Foundation

final class MyModel {
    private lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "Users")
        container.loadPersistentStores(completionHandler: { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved error \(error), \(error.userInfo)")
            }
        })
        return container
    }()

    func save() {
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

    func load() {
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
