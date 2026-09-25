# Atlas Tasks

Tasks are shared work items assigned to an Atlas user. Any signed-in teammate can view and manage them. An account link and due date are optional. The due date is the expected completion date and schedules a Slack message to the assignee at 09:00 Coordinated Universal Time on that date, or immediately if the task is created or reassigned after that time. The task's `remind_at` time schedules another Slack message to the assignee through the company app. A reminder set in the past is delivered immediately.

The notification workers check the task's current version, open status, and delivery timestamp before sending. Editing the relevant date or assignee increments its version so old scheduled jobs cannot send. Reassignment schedules pending notifications for the new assignee, including notifications whose time has passed. Completing a task leaves its scheduled jobs harmless. Each notification version has a stable Slack client message ID to reduce duplicates after an ambiguous retry.

Slack user resolution uses a company Slack user with the assignee's email, then falls back to Slack's email lookup. Delivery failures retry through Oban. Keep reminder scheduling and task mutations in `Atlas.Tasks`, and expose new task actions through the dashboard and Atlas tools together.
