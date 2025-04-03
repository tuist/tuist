---
title: "Tuist is now SOC 2 Type II compliant"
category: "product"
tags: ["security", "soc2", "safety"]
excerpt: "We are thrilled to announce that Tuist is now SOC 2 Type II compliant"
author: pepicrft
og_image_path: /marketing/images/blog/2025/04/03/soc2/og.jpeg
---

SOC Type II compliance is a big step in proving our commitment to security and reliability. Whether you’re using Tuist to manage Xcode projects, streamline development, or handle sensitive data, you can trust that we take security seriously.  

Unlike SOC 2 Type I, which is a one-time assessment, **Type II requires us to demonstrate consistent security practices over several months**. This means our security isn’t just a snapshot—it’s baked into how we operate every day.  

Here’s why we pursued SOC 2, how we tackled compliance, and what we learned along the way.  

## Why go for SOC 2?  

Security isn’t just a nice-to-have—it’s a necessity. As more teams adopted Tuist, we found ourselves answering security questionnaires and explaining our security measures over and over again. We wanted a **clear, industry-recognized way to show that we handle your data responsibly**.  

SOC 2 helps with that. It’s designed for SaaS companies like us and focuses on the security and privacy of customer data. Achieving compliance means we’ve implemented strong controls and had them independently verified.  

Another reason we started early? **Future-proofing.** Security is easiest when it’s built into a company’s DNA. Instead of scrambling to meet compliance as we scale, we’re setting a strong foundation now—so security never becomes an afterthought.  

## What is SOC 2 Type II?  

SOC 2 is a security and compliance framework developed by the **American Institute of CPAs (AICPA)**. It evaluates companies on five Trust Services Criteria:  

- **Security** – Protecting systems and data from unauthorized access.  
- **Availability** – Ensuring services are reliable and accessible.  
- **Processing Integrity** – Making sure systems operate as expected.  
- **Confidentiality** – Safeguarding sensitive data.  
- **Privacy** – Managing personal data responsibly.  

SOC 2 has two types of audits:  

- **Type I** – A one-time assessment of security policies and controls.  
- **Type II** – A long-term audit (6–12 months) proving those controls are consistently followed.  

We went for **Type II** because we didn’t just want to pass a one-time check—we wanted to show we take security seriously, every day.  

## Picking the right compliance tool  

We needed a compliance tool that worked well with our stack—[Supabase](https://supabase.com/), [GitHub](https://github.com/), [Google Workspace](https://workspace.google.com/), and [Tigris](https://www.tigrisdata.com/). After evaluating:  

- [Vanta](https://www.vanta.com/)  
- [Drata](https://drata.com/)  
- [Tugboat Logic](https://tugboatlogic.com/)  

We landed on **Vanta**. It had the best automation, worked smoothly with our existing tools, and didn’t require overly intrusive permissions (some alternatives wanted full GitHub access—not happening).  

## Finding the right auditor  

Once we had Vanta set up and running, we needed an independent auditor to review our security practices. Vanta connected us with several options, and we picked one that specializes in SaaS security audits.  

The process started with a **scoping call**, where we determined which systems and processes would be reviewed. Then, we set a date for the audit’s **Type II snapshot**—a point in time that proves our policies were in place and working as intended.  

## Preparing for the audit  

The months leading up to the audit were all about **proving that security was part of our daily workflow**. Vanta’s osquery agent helped us track:  

- **Device security** – Ensuring all company laptops had encryption, screen locks, and proper access controls.  
- **Policy enforcement** – Creating and refining security policies for access control, data management, and asset tracking.  
- **Compliance checks** – Verifying we had proper logging, monitoring, and security controls in place.  

Another key step was reviewing our vendor security. If we were being audited, we wanted our vendors to meet the same standards. So we asked for **SOC 2 reports** from any service we relied on that handled sensitive data.  

## Open security policies  

We believe in transparency, which is why we’ve made our security policies **public** in the [Tuist Handbook](https://handbook.tuist.dev).  

This includes:  

- How we manage access control.  
- How we protect user and project data.  
- Our incident response process.  

Security shouldn’t be a black box. By sharing our policies, we make it clear how we operate and hold ourselves accountable to our users.  

## Making SOC 2 work for us  

One thing we didn’t want? **Mindless checkbox compliance.** Every security control we implemented had to make sense for Tuist—not just to satisfy an auditor.  

For example:  

- **Access Reviews** – Instead of a rigid quarterly review, we built security checks into our onboarding/offboarding process to ensure permissions stay up to date.  
- **Incident Response** – Rather than a generic playbook, we tailored our process to match how we actually work and respond to security events.  
- **Security Training** – We kept it practical. Sure, we still had to sit through the “don’t reuse passwords” training video, but we focused on **real security risks** our team faces.  

## Launching the Tuist Security Center  

We’re also launching the **[Tuist Security Center](https://security.tuist.dev)**, a hub where you can:  

- Learn how we protect your data.  
- Request a copy of our SOC 2 audit report.  
- Get in touch with our security team at [security@tuist.dev](mailto:security@tuist.dev).  

Security is an ongoing effort, not a one-time project. We’ll continue improving our security posture, refining our processes, and making sure Tuist stays a trusted tool for developers everywhere.  

If you’re working toward SOC 2 yourself, we hope this breakdown helps. It’s a big effort, but it’s worth it—not just for compliance, but for building a truly secure product. 🚀
