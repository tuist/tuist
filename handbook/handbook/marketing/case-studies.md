---
{
  "title": "Case studies",
  "titleTemplate": ":title | Marketing | Tuist Handbook",
  "description": "This document provides guidelines for creating case studies that showcase the impact of Tuist on organizations' projects."
}
---
# Case studies

Case studies are a useful tool to **celebrate the success of Tuist users and showcase the impact of Tuist on their projects.** They provide a real-world perspective on how Tuist has helped teams overcome challenges and achieve their goals.
It helps future customers understand the value of Tuist through the lenses of existing organizations, giving Tuist credibility and trustworthiness.

Therefore, we should suggest organizations to share their stories with us, so we can create case studies that can be shared on our website, blog, and social media channels. Note that some might not feel comfortable sharing their stories publicly, so we should respect their privacy and only publish case studies with their explicit consent.

Once an organization has agreed to share their story, you can use the following template to create a case study:

- **Name:** The name of the organization.
- **URL:** A link to the organization's website.
- **Solutions:** The features of Tuist that the organization used to solve their challenges.
- **The problem/challenge:** One pragraph describing the challenges the organization faced.
- **Why Tuist?:** One paragraph explaining why the organization chose Tuist. You can use bullet points to list the various reasons.
- **The results:** A list of advantages and improvements that the organization experienced after adopting Tuist. Each one should be a title followed by a paragraph describing the impact.
- **Using Tuist since:** The month the organization started using Tuist, confirmed by them. It appears on the story and in the home page carousel.
- **Before and after:** The figures the organization measured before and after adopting Tuist, such as CI pull request time, clean or incremental build time, or test time. For each, ask for the metric, both values with units, and how and over what period they were measured. Ask what else changed in the same period, and say so in the story.

You can use [this Supabase case study](https://supabase.com/customers/voypost) as a reference.

## Customer dates and before/after figures

Recognizable customers with real numbers are our strongest pitch, so stories show them up front: the story page shows the "Using Tuist since" month and a before/after table above the story text, and the home page carousel shows the month too. Both come from the story's front matter in `server/priv/marketing/case_studies/`:

```yaml
onboarded_date: "2022-06-01"
results:
  - metric: "P50 pull request time"
    before: "52 min"
    after: "15 min"
```

- **Never estimate.** Only publish a date or figure the organization gave us or approved. A result needs all three fields; a relative claim without a baseline ("2.5x faster", "more than tripled") stays in the prose until we have both values.
- **Put the headline figure first.** The table lists results in front-matter order.
- **Mark what is missing.** Leave a commented placeholder in the front matter, such as `# onboarded_date: "YYYY-MM-DD"  # TODO: confirm with <company>`, so the gap is visible to whoever next talks to the customer.
- **Use a benchmark for our own experiments.** When we measure a project ourselves, as in [Codex cut Mastodon iOS clean builds 80%](https://tuist.dev/blog/2026/02/02/migrating-mastodon-ios-to-tuist-with-codex), publish the scenarios, commands, and a results table with the number of runs so readers can reproduce it.