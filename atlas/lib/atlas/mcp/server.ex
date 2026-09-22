defmodule Atlas.MCP.Server do
  @moduledoc """
  Atlas MCP server. Exposes a set of tools that surface account
  context (timeline events, contacts, invoices, account attention, overview summary) so
  external agents can compose follow-ups and draft emails locally with
  full context.
  """

  alias Atlas.Audit
  alias Atlas.MCP.Prompts.GenerateEnterpriseContract, as: GenerateEnterpriseContractPrompt
  alias Atlas.MCP.Proxy
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ActivateInsurancePolicy
  alias Atlas.MCP.Tools.ActOnAccountAttentionSuggestion
  alias Atlas.MCP.Tools.ActOnBriefItem
  alias Atlas.MCP.Tools.AddAssetToInsurance
  alias Atlas.MCP.Tools.AddEmailAudienceSubscriber
  alias Atlas.MCP.Tools.AddSpecComment
  alias Atlas.MCP.Tools.AddSupportThreadNote
  alias Atlas.MCP.Tools.AssignAsset
  alias Atlas.MCP.Tools.AttachDocumentToFinancing
  alias Atlas.MCP.Tools.AttachDocumentToInsuranceClaim
  alias Atlas.MCP.Tools.AttachDocumentToInsurancePolicy
  alias Atlas.MCP.Tools.BrowseUrl
  alias Atlas.MCP.Tools.CancelInsurancePolicy
  alias Atlas.MCP.Tools.CheckLetterDelivery
  alias Atlas.MCP.Tools.CheckOutAirGappedLicense
  alias Atlas.MCP.Tools.CompleteOutreachNextStep
  alias Atlas.MCP.Tools.ConfirmTaxCertificateDelivery
  alias Atlas.MCP.Tools.ConvertGTMOpportunity
  alias Atlas.MCP.Tools.CreateAccount
  alias Atlas.MCP.Tools.CreateAccountNote
  alias Atlas.MCP.Tools.CreateAccountTerm
  alias Atlas.MCP.Tools.CreateAsset
  alias Atlas.MCP.Tools.CreateBlogPostIdea
  alias Atlas.MCP.Tools.CreateBlogPostIdeaComment
  alias Atlas.MCP.Tools.CreateContact
  alias Atlas.MCP.Tools.CreateCrossDomainClaim
  alias Atlas.MCP.Tools.CreateDataCenter
  alias Atlas.MCP.Tools.CreateDocumentUpload
  alias Atlas.MCP.Tools.CreateEmailAudience
  alias Atlas.MCP.Tools.CreateEmailSubscriber
  alias Atlas.MCP.Tools.CreateEngineeringDomain
  alias Atlas.MCP.Tools.CreateEngineeringProject
  alias Atlas.MCP.Tools.CreateFeatureInterest
  alias Atlas.MCP.Tools.CreateFinancing
  alias Atlas.MCP.Tools.CreateInsurancePolicy
  alias Atlas.MCP.Tools.CreateLetterDocumentUpload
  alias Atlas.MCP.Tools.CreateLicense
  alias Atlas.MCP.Tools.CreateNote
  alias Atlas.MCP.Tools.CreatePostmortem
  alias Atlas.MCP.Tools.CreatePostmortemActionItem
  alias Atlas.MCP.Tools.CreateSocialChannelIdea
  alias Atlas.MCP.Tools.CreateSocialPostRevision
  alias Atlas.MCP.Tools.CreateSpec
  alias Atlas.MCP.Tools.CreateStripeDraftInvoice
  alias Atlas.MCP.Tools.DecommissionDataCenter
  alias Atlas.MCP.Tools.DeleteAccountTerm
  alias Atlas.MCP.Tools.DeleteAsset
  alias Atlas.MCP.Tools.DeleteDataCenter
  alias Atlas.MCP.Tools.DeleteEmailAudience
  alias Atlas.MCP.Tools.DeleteEngineeringDomain
  alias Atlas.MCP.Tools.DeleteEngineeringProject
  alias Atlas.MCP.Tools.DeleteFinancing
  alias Atlas.MCP.Tools.DeleteInsurancePolicy
  alias Atlas.MCP.Tools.DeletePostmortem
  alias Atlas.MCP.Tools.DeletePostmortemActionItem
  alias Atlas.MCP.Tools.DeleteSocialChannelIdea
  alias Atlas.MCP.Tools.DeleteSocialPostRevision
  alias Atlas.MCP.Tools.DeleteSpec
  alias Atlas.MCP.Tools.DeleteSpecComment
  alias Atlas.MCP.Tools.DescribeTuistClickhouseTable
  alias Atlas.MCP.Tools.DescribeTuistPostgresTable
  alias Atlas.MCP.Tools.DetachDocumentFromFinancing
  alias Atlas.MCP.Tools.DetachDocumentFromInsuranceClaim
  alias Atlas.MCP.Tools.DetachDocumentFromInsurancePolicy
  alias Atlas.MCP.Tools.DismissOutreachNextStep
  alias Atlas.MCP.Tools.DisposeAsset
  alias Atlas.MCP.Tools.EditAssetMetadata
  alias Atlas.MCP.Tools.EditDataCenter
  alias Atlas.MCP.Tools.EditFinancingMetadata
  alias Atlas.MCP.Tools.EditFinancingPaymentDecomposition
  alias Atlas.MCP.Tools.EditInsuranceMember
  alias Atlas.MCP.Tools.EditInsurancePolicy
  alias Atlas.MCP.Tools.EditStripeDraftInvoice
  alias Atlas.MCP.Tools.EnrichGTMOpportunityContacts
  alias Atlas.MCP.Tools.EnrollOutreachCandidate
  alias Atlas.MCP.Tools.EnrollOutreachContact
  alias Atlas.MCP.Tools.ExercisePurchaseOption
  alias Atlas.MCP.Tools.ExpireInsurancePolicy
  alias Atlas.MCP.Tools.ExtendLicense
  alias Atlas.MCP.Tools.FinalizeDocumentUpload
  alias Atlas.MCP.Tools.FinalizeLetterDocumentUpload
  alias Atlas.MCP.Tools.FinanceAddTransactionAttachment
  alias Atlas.MCP.Tools.FinanceDeleteTransactionAttachment
  alias Atlas.MCP.Tools.FinanceGetTransaction
  alias Atlas.MCP.Tools.FinanceListTransactionAttachments
  alias Atlas.MCP.Tools.GenerateAccountAttentionSuggestions
  alias Atlas.MCP.Tools.GenerateEnterpriseContract
  alias Atlas.MCP.Tools.GenerateLeadershipBrief
  alias Atlas.MCP.Tools.GenerateOutreachNextStep
  alias Atlas.MCP.Tools.GetAccount
  alias Atlas.MCP.Tools.GetAccountFeatureUsage
  alias Atlas.MCP.Tools.GetAsset
  alias Atlas.MCP.Tools.GetAssetBookValue
  alias Atlas.MCP.Tools.GetAuditActivity
  alias Atlas.MCP.Tools.GetBlogPostIdea
  alias Atlas.MCP.Tools.GetBrief
  alias Atlas.MCP.Tools.GetContractTemplate
  alias Atlas.MCP.Tools.GetDataCenter
  alias Atlas.MCP.Tools.GetDocument
  alias Atlas.MCP.Tools.GetDomainErrorDsn
  alias Atlas.MCP.Tools.GetEmailAudience
  alias Atlas.MCP.Tools.GetEngineeringDomain
  alias Atlas.MCP.Tools.GetEngineeringProject
  alias Atlas.MCP.Tools.GetErrorIssue
  alias Atlas.MCP.Tools.GetEvent
  alias Atlas.MCP.Tools.GetFeatureInterest
  alias Atlas.MCP.Tools.GetFinanceExpenseHistory
  alias Atlas.MCP.Tools.GetFinanceExpenseReconciliation
  alias Atlas.MCP.Tools.GetFinanceOverview
  alias Atlas.MCP.Tools.GetFinancing
  alias Atlas.MCP.Tools.GetGTMOpportunity
  alias Atlas.MCP.Tools.GetInsurancePolicy
  alias Atlas.MCP.Tools.GetNote
  alias Atlas.MCP.Tools.GetOutreachContact
  alias Atlas.MCP.Tools.GetOutreachNextStep
  alias Atlas.MCP.Tools.GetPostmortem
  alias Atlas.MCP.Tools.GetPostmortemActionItem
  alias Atlas.MCP.Tools.GetProjectErrorDsn
  alias Atlas.MCP.Tools.GetSocialChannelIdea
  alias Atlas.MCP.Tools.GetSocialPostRevision
  alias Atlas.MCP.Tools.GetSpec
  alias Atlas.MCP.Tools.GetSupportThread
  alias Atlas.MCP.Tools.IgnoreErrorIssue
  alias Atlas.MCP.Tools.ImportFinancingSchedule
  alias Atlas.MCP.Tools.InstallAssetInDataCenter
  alias Atlas.MCP.Tools.LinkAssetToInsuranceClaim
  alias Atlas.MCP.Tools.LinkProjectDomain
  alias Atlas.MCP.Tools.LinkProjectRepository
  alias Atlas.MCP.Tools.ListAccountAttentionSuggestions
  alias Atlas.MCP.Tools.ListAccountContacts
  alias Atlas.MCP.Tools.ListAccountEvents
  alias Atlas.MCP.Tools.ListAccountFeatureInterests
  alias Atlas.MCP.Tools.ListAccountFeatureUsage
  alias Atlas.MCP.Tools.ListAccountIncidentContacts
  alias Atlas.MCP.Tools.ListAccountInvoices
  alias Atlas.MCP.Tools.ListAccountLetters
  alias Atlas.MCP.Tools.ListAccounts
  alias Atlas.MCP.Tools.ListAccountServiceLevels
  alias Atlas.MCP.Tools.ListAccountTerms
  alias Atlas.MCP.Tools.ListAssetAssignments
  alias Atlas.MCP.Tools.ListAssetEvents
  alias Atlas.MCP.Tools.ListAssetFinancings
  alias Atlas.MCP.Tools.ListAssets
  alias Atlas.MCP.Tools.ListAuditActivities
  alias Atlas.MCP.Tools.ListBlogPostIdeas
  alias Atlas.MCP.Tools.ListBriefs
  alias Atlas.MCP.Tools.ListContractTemplates
  alias Atlas.MCP.Tools.ListCrossDomainClaims
  alias Atlas.MCP.Tools.ListDataCenters
  alias Atlas.MCP.Tools.ListDocuments
  alias Atlas.MCP.Tools.ListEmailAudiences
  alias Atlas.MCP.Tools.ListEmailSubscribers
  alias Atlas.MCP.Tools.ListEngineeringDomains
  alias Atlas.MCP.Tools.ListEngineeringProjects
  alias Atlas.MCP.Tools.ListErrorIssues
  alias Atlas.MCP.Tools.ListFeatureInterests
  alias Atlas.MCP.Tools.ListFinanceAccounts
  alias Atlas.MCP.Tools.ListFinanceCategories
  alias Atlas.MCP.Tools.ListFinanceInvoices
  alias Atlas.MCP.Tools.ListFinanceTransactions
  alias Atlas.MCP.Tools.ListFinancings
  alias Atlas.MCP.Tools.ListGTMAdvocates
  alias Atlas.MCP.Tools.ListGTMOpportunities
  alias Atlas.MCP.Tools.ListGTMResearchTopics
  alias Atlas.MCP.Tools.ListInsurancePolicies
  alias Atlas.MCP.Tools.ListInvoices
  alias Atlas.MCP.Tools.ListLicenses
  alias Atlas.MCP.Tools.ListNotes
  alias Atlas.MCP.Tools.ListOutreachCandidates
  alias Atlas.MCP.Tools.ListOutreachContacts
  alias Atlas.MCP.Tools.ListPostmortemActionItems
  alias Atlas.MCP.Tools.ListPostmortems
  alias Atlas.MCP.Tools.ListProductTraces
  alias Atlas.MCP.Tools.ListSocialChannelIdeas
  alias Atlas.MCP.Tools.ListSocialPostRevisions
  alias Atlas.MCP.Tools.ListSpecComments
  alias Atlas.MCP.Tools.ListSpecs
  alias Atlas.MCP.Tools.ListSupportThreads
  alias Atlas.MCP.Tools.ListTuistClickhouseTables
  alias Atlas.MCP.Tools.ListTuistPostgresTables
  alias Atlas.MCP.Tools.ListUpcomingRenewals
  alias Atlas.MCP.Tools.MarkAccountNotAccount
  alias Atlas.MCP.Tools.MarkAssetInRepair
  alias Atlas.MCP.Tools.MarkAssetLost
  alias Atlas.MCP.Tools.MarkAssetRepaired
  alias Atlas.MCP.Tools.MarkAssetReturnedToLessor
  alias Atlas.MCP.Tools.MarkFinancingPaidOff
  alias Atlas.MCP.Tools.MatchFinancingPayment
  alias Atlas.MCP.Tools.NotifyGTMOpportunity
  alias Atlas.MCP.Tools.PlaceAssetInService
  alias Atlas.MCP.Tools.PrepareGTMOpportunityOutreach
  alias Atlas.MCP.Tools.QueryTuistClickhouse
  alias Atlas.MCP.Tools.QueryTuistPostgres
  alias Atlas.MCP.Tools.RecallMemory
  alias Atlas.MCP.Tools.RecordAssetIncident
  alias Atlas.MCP.Tools.RecordAssetNote
  alias Atlas.MCP.Tools.RecordAssetRepair
  alias Atlas.MCP.Tools.RecordAssetWarrantyExtension
  alias Atlas.MCP.Tools.RecordFeatureInterest
  alias Atlas.MCP.Tools.RecordInsuranceClaim
  alias Atlas.MCP.Tools.RecordOutreachEvent
  alias Atlas.MCP.Tools.RecoverAsset
  alias Atlas.MCP.Tools.RejectOutreachCandidate
  alias Atlas.MCP.Tools.RemoveAssetFromInsurance
  alias Atlas.MCP.Tools.ReplyToSupportThread
  alias Atlas.MCP.Tools.RequestSpecReview
  alias Atlas.MCP.Tools.RequestTaxCertificateLetter
  alias Atlas.MCP.Tools.ResolveErrorIssue
  alias Atlas.MCP.Tools.RetireAsset
  alias Atlas.MCP.Tools.ReturnAsset
  alias Atlas.MCP.Tools.ReturnFinancing
  alias Atlas.MCP.Tools.ReviewGTMOpportunity
  alias Atlas.MCP.Tools.RotateDomainErrorDsn
  alias Atlas.MCP.Tools.RotateProjectErrorDsn
  alias Atlas.MCP.Tools.RunGTMSignalSearch
  alias Atlas.MCP.Tools.SaveMemory
  alias Atlas.MCP.Tools.SearchApolloOutreach
  alias Atlas.MCP.Tools.SearchAtlas
  alias Atlas.MCP.Tools.SearchDocuments
  alias Atlas.MCP.Tools.SearchNotes
  alias Atlas.MCP.Tools.SearchWeb
  alias Atlas.MCP.Tools.SendEmailBroadcast
  alias Atlas.MCP.Tools.SetFinancingAccountingTreatment
  alias Atlas.MCP.Tools.SetFinancingLines
  alias Atlas.MCP.Tools.TerminateFinancing
  alias Atlas.MCP.Tools.UnlinkAssetFromInsuranceClaim
  alias Atlas.MCP.Tools.UnlinkProjectDomain
  alias Atlas.MCP.Tools.UnlinkProjectRepository
  alias Atlas.MCP.Tools.UnsubscribeEmailAudienceSubscriber
  alias Atlas.MCP.Tools.UpdateAccount
  alias Atlas.MCP.Tools.UpdateAccountTerm
  alias Atlas.MCP.Tools.UpdateContact
  alias Atlas.MCP.Tools.UpdateEmailSubscriber
  alias Atlas.MCP.Tools.UpdateEngineeringDomain
  alias Atlas.MCP.Tools.UpdateEngineeringProject
  alias Atlas.MCP.Tools.UpdateFeatureInterestAccountContext
  alias Atlas.MCP.Tools.UpdateInsuranceClaim
  alias Atlas.MCP.Tools.UpdateNote
  alias Atlas.MCP.Tools.UpdatePostmortem
  alias Atlas.MCP.Tools.UpdatePostmortemActionItem
  alias Atlas.MCP.Tools.UpdateSocialChannelIdea
  alias Atlas.MCP.Tools.UpdateSocialPostRevision
  alias Atlas.MCP.Tools.UpdateSpec
  alias Atlas.MCP.Tools.UpdateSpecComment
  alias Atlas.MCP.Tools.UpdateSupportThread
  alias Atlas.MCP.Tools.UploadPostalLetter

  @name "atlas"
  @version "0.2.0"
  @title "Atlas"
  @description "Tuist's source of truth for customer, commercial, contract, finance, email audience, and operational context."
  @instructions """
  Use Atlas tools whenever a request depends on Tuist's internal customer, commercial, contract, finance, or operational context.

  Notes are shared Markdown documents available to every authenticated user. Use
  `create_note` and `update_note` with a level-one heading in the Markdown,
  which becomes the note title. Use `search_notes` for lexical and semantic
  retrieval.

  For monthly cost evolution, call `get_finance_expense_history`. For a single
  monthly expense total, call `get_finance_expense_reconciliation`. They
  aggregate every matching cash expense across all synced finance accounts. Do
  not calculate a total by summing a bounded `list_finance_transactions`
  response. A result with `complete: false` is not a final total; explain its
  exclusions instead.

  For transaction attachment management, use `finance_get_transaction` to inspect
  a single transaction and its live attachments, `finance_list_transaction_attachments`
  to list attachments for a specific transaction, `finance_add_transaction_attachment`
  to attach an Atlas document to a transaction that lacks a receipt or supporting file,
  and `finance_delete_transaction_attachment` to remove an incorrect or duplicate
  attachment. All finance attachment tools are executive-only.

  For any request to create, draft, prepare, generate, or fill an order form, enterprise contract, Master Services Agreement, or contract package:
  1. Call `generate_enterprise_contract` with `document_scope` set to `order_form` or `contract_package`. Follow the workflow it returns.
  2. Call `get_account` to retrieve the customer identity, legal, billing, signatory, and commercial term fields. Prefer explicit values in the user's current request over pasted conversation context, and prefer both over older values stored on the account.
  3. Call `list_contract_templates`, then `get_contract_template` for the appropriate official Word template. The latter attaches the binary template directly, so use that embedded resource instead of trying browser, desktop-control, or terminal hand-offs. Never create a substitute document from scratch.
  4. If the user asks only for an order form, fetch only the appropriate order form rather than the full contract package. Use `order-form-tuist-hosted.docx` for a hosted deal and `order-form-self-hosted.docx` for a self-hosted deal. Ask the user when the hosting model cannot be determined from their request, conversation context, or the latest commercial term.
  5. Do not invent missing legal, billing, signatory, date, or renewal fields. Ask the user for required values that are absent from both their request and Atlas.

  When account evidence may imply a useful next follow-up, call `generate_account_attention_suggestions`. Treat the result as a suggestion for review and use `list_account_attention_suggestions` to avoid repeating an unresolved or dismissed suggestion. Use `act_on_account_attention_suggestion` only after the user explicitly chooses to mark a suggestion done, snooze it, or dismiss it. Use `update_account` with `attention_context` when the user provides strategic account guidance, such as why a product capability is important to the relationship.

  For outbound prospecting, Apollo is only a search provider and Atlas is the source of truth. Use `search_apollo_outreach` to discover people, `list_outreach_candidates` to review the Atlas-owned queue, and `enroll_outreach_candidate` or `reject_outreach_candidate` to make an explicit decision. Do not treat Apollo saved contacts as outreach state. Use `get_outreach_next_step` to read Atlas's guided suggestion. Use `generate_outreach_next_step` when the user asks for a fresh analysis. Only call `complete_outreach_next_step` after the user confirms the action happened, and use `dismiss_outreach_next_step` with specific feedback when the suggestion is not useful. Atlas never sends LinkedIn invitations or messages automatically.

  For group email, Atlas owns subscribers, audiences, and delivery history. Use the email subscriber and audience tools to inspect or prepare recipients. Only call `send_email_broadcast` when the user explicitly asks to send or queue the broadcast, because it immediately snapshots current subscribed recipients and queues delivery.

  Use `list_briefs` and `get_brief` to understand leadership attention across domains. Treat brief items as suggested coordination moves, not authoritative facts; inspect their evidence classes. Use `act_on_brief_item` only when the user explicitly asks to own, acknowledge, resolve, rate, or suppress an item. Cross-domain claims require exact or explicitly verified links and at least two supporting domain records.
  """

  # `outputSchema` and `structuredContent` were introduced in 2025-06-18. EMCP still
  # answers `initialize` with 2025-03-26, so Atlas negotiates the version itself.
  @latest_protocol_version "2025-06-18"
  @supported_protocol_versions [@latest_protocol_version, "2025-03-26"]
  @contract_tools [
    GenerateEnterpriseContract,
    ListContractTemplates,
    GetContractTemplate
  ]
  @prompts [GenerateEnterpriseContractPrompt]
  @finance_tools [
    ListInvoices,
    GetFinanceOverview,
    GetFinanceExpenseHistory,
    GetFinanceExpenseReconciliation,
    ListFinanceAccounts,
    ListFinanceCategories,
    ListFinanceInvoices,
    ListFinanceTransactions,
    ListAccountInvoices,
    CreateStripeDraftInvoice,
    EditStripeDraftInvoice,
    FinanceGetTransaction,
    FinanceListTransactionAttachments,
    FinanceAddTransactionAttachment,
    FinanceDeleteTransactionAttachment
  ]
  @document_tools [
    ListDocuments,
    GetDocument,
    SearchDocuments,
    CreateDocumentUpload,
    FinalizeDocumentUpload,
    ListAccountServiceLevels,
    ListAccountIncidentContacts
  ]
  @hardware_tools [
    ListAssets,
    GetAsset,
    ListAssetFinancings,
    ListAssetAssignments,
    ListAssetEvents,
    GetAssetBookValue,
    CreateAsset,
    EditAssetMetadata,
    DeleteAsset,
    PlaceAssetInService,
    AssignAsset,
    ReturnAsset,
    MarkAssetInRepair,
    MarkAssetRepaired,
    MarkAssetLost,
    RecoverAsset,
    RetireAsset,
    DisposeAsset,
    RecordAssetRepair,
    RecordAssetIncident,
    RecordAssetNote,
    RecordAssetWarrantyExtension,
    MarkAssetReturnedToLessor,
    ListDataCenters,
    GetDataCenter,
    CreateDataCenter,
    EditDataCenter,
    DecommissionDataCenter,
    DeleteDataCenter,
    InstallAssetInDataCenter,
    ListInsurancePolicies,
    GetInsurancePolicy,
    CreateInsurancePolicy,
    EditInsurancePolicy,
    ActivateInsurancePolicy,
    ExpireInsurancePolicy,
    CancelInsurancePolicy,
    DeleteInsurancePolicy,
    AddAssetToInsurance,
    RemoveAssetFromInsurance,
    EditInsuranceMember,
    RecordInsuranceClaim,
    UpdateInsuranceClaim,
    LinkAssetToInsuranceClaim,
    UnlinkAssetFromInsuranceClaim,
    AttachDocumentToInsurancePolicy,
    DetachDocumentFromInsurancePolicy,
    AttachDocumentToInsuranceClaim,
    DetachDocumentFromInsuranceClaim,
    ListFinancings,
    GetFinancing,
    CreateFinancing,
    EditFinancingMetadata,
    AttachDocumentToFinancing,
    DetachDocumentFromFinancing,
    DeleteFinancing,
    SetFinancingLines,
    SetFinancingAccountingTreatment,
    ImportFinancingSchedule,
    MatchFinancingPayment,
    EditFinancingPaymentDecomposition,
    MarkFinancingPaidOff,
    ExercisePurchaseOption,
    ReturnFinancing,
    TerminateFinancing
  ]
  @admin_tools [
    ListLicenses,
    CreateLicense,
    ExtendLicense,
    CheckOutAirGappedLicense,
    ListAuditActivities,
    GetAuditActivity,
    ListBriefs,
    GetBrief,
    ActOnBriefItem,
    GenerateLeadershipBrief,
    ListCrossDomainClaims,
    CreateCrossDomainClaim,
    RequestTaxCertificateLetter,
    CreateLetterDocumentUpload,
    FinalizeLetterDocumentUpload,
    UploadPostalLetter,
    ConfirmTaxCertificateDelivery,
    ListAccountLetters,
    CheckLetterDelivery
  ]
  @tuist_server_tools [
    QueryTuistPostgres,
    ListTuistPostgresTables,
    DescribeTuistPostgresTable,
    QueryTuistClickhouse,
    ListTuistClickhouseTables,
    DescribeTuistClickhouseTable
  ]
  @static_tools [
    ListEngineeringProjects,
    GetEngineeringProject,
    CreateEngineeringProject,
    UpdateEngineeringProject,
    DeleteEngineeringProject,
    ListPostmortems,
    GetPostmortem,
    CreatePostmortem,
    UpdatePostmortem,
    DeletePostmortem,
    ListPostmortemActionItems,
    GetPostmortemActionItem,
    CreatePostmortemActionItem,
    UpdatePostmortemActionItem,
    DeletePostmortemActionItem,
    ListSpecs,
    GetSpec,
    CreateSpec,
    UpdateSpec,
    DeleteSpec,
    RequestSpecReview,
    ListSpecComments,
    AddSpecComment,
    UpdateSpecComment,
    DeleteSpecComment,
    ListEngineeringDomains,
    GetEngineeringDomain,
    CreateEngineeringDomain,
    UpdateEngineeringDomain,
    DeleteEngineeringDomain,
    LinkProjectDomain,
    UnlinkProjectDomain,
    LinkProjectRepository,
    UnlinkProjectRepository,
    GetProjectErrorDsn,
    RotateProjectErrorDsn,
    GetDomainErrorDsn,
    RotateDomainErrorDsn,
    # CreateProjectWebhook / DeleteProjectWebhook are held back until
    # Projects.ingest_webhook/4 stops returning :not_implemented. Registering
    # them would hand agents URLs that return 404 in production.
    ListErrorIssues,
    GetErrorIssue,
    ResolveErrorIssue,
    IgnoreErrorIssue,
    ListLicenses,
    CreateLicense,
    ExtendLicense,
    CheckOutAirGappedLicense,
    ListAuditActivities,
    GetAuditActivity,
    ListBriefs,
    GetBrief,
    ActOnBriefItem,
    GenerateLeadershipBrief,
    ListCrossDomainClaims,
    CreateCrossDomainClaim,
    RequestTaxCertificateLetter,
    CreateLetterDocumentUpload,
    FinalizeLetterDocumentUpload,
    UploadPostalLetter,
    ConfirmTaxCertificateDelivery,
    ListAccountLetters,
    CheckLetterDelivery,
    ListEmailSubscribers,
    CreateEmailSubscriber,
    UpdateEmailSubscriber,
    ListEmailAudiences,
    GetEmailAudience,
    CreateEmailAudience,
    DeleteEmailAudience,
    AddEmailAudienceSubscriber,
    UnsubscribeEmailAudienceSubscriber,
    SendEmailBroadcast,
    FinanceAddTransactionAttachment,
    FinanceDeleteTransactionAttachment,
    FinanceGetTransaction,
    FinanceListTransactionAttachments,
    ListProductTraces,
    ListSupportThreads,
    GetSupportThread,
    ReplyToSupportThread,
    AddSupportThreadNote,
    UpdateSupportThread,
    ListAccounts,
    ListUpcomingRenewals,
    CreateAccount,
    GetAccount,
    GetAccountFeatureUsage,
    ListAccountFeatureUsage,
    ListAccountEvents,
    GetEvent,
    ListFeatureInterests,
    CreateFeatureInterest,
    GetFeatureInterest,
    ListAccountFeatureInterests,
    ListInvoices,
    GetFinanceOverview,
    GetFinanceExpenseHistory,
    GetFinanceExpenseReconciliation,
    ListFinanceAccounts,
    ListFinanceCategories,
    ListFinanceInvoices,
    ListFinanceTransactions,
    ListAccountContacts,
    ListAccountIncidentContacts,
    ListAccountInvoices,
    CreateStripeDraftInvoice,
    EditStripeDraftInvoice,
    ActOnAccountAttentionSuggestion,
    ListAccountAttentionSuggestions,
    ListAccountServiceLevels,
    ListDocuments,
    GetDocument,
    SearchDocuments,
    CreateDocumentUpload,
    FinalizeDocumentUpload,
    ListNotes,
    GetNote,
    SearchNotes,
    CreateNote,
    UpdateNote,
    UpdateAccount,
    MarkAccountNotAccount,
    GenerateAccountAttentionSuggestions,
    CreateAccountNote,
    CreateContact,
    UpdateContact,
    ListBlogPostIdeas,
    GetBlogPostIdea,
    CreateBlogPostIdea,
    CreateBlogPostIdeaComment,
    ListSocialChannelIdeas,
    GetSocialChannelIdea,
    CreateSocialChannelIdea,
    UpdateSocialChannelIdea,
    DeleteSocialChannelIdea,
    ListSocialPostRevisions,
    GetSocialPostRevision,
    CreateSocialPostRevision,
    UpdateSocialPostRevision,
    DeleteSocialPostRevision,
    ListGTMResearchTopics,
    ListGTMAdvocates,
    ListGTMOpportunities,
    GetGTMOpportunity,
    NotifyGTMOpportunity,
    PrepareGTMOpportunityOutreach,
    ReviewGTMOpportunity,
    ConvertGTMOpportunity,
    EnrichGTMOpportunityContacts,
    EnrollOutreachContact,
    SearchApolloOutreach,
    ListOutreachCandidates,
    EnrollOutreachCandidate,
    RejectOutreachCandidate,
    ListOutreachContacts,
    GetOutreachContact,
    GetOutreachNextStep,
    GenerateOutreachNextStep,
    CompleteOutreachNextStep,
    DismissOutreachNextStep,
    RecordOutreachEvent,
    RecordFeatureInterest,
    UpdateFeatureInterestAccountContext,
    RunGTMSignalSearch,
    SaveMemory,
    RecallMemory,
    SearchAtlas,
    GenerateEnterpriseContract,
    ListContractTemplates,
    GetContractTemplate,
    ListAccountTerms,
    CreateAccountTerm,
    UpdateAccountTerm,
    DeleteAccountTerm,
    SearchWeb,
    BrowseUrl,
    QueryTuistPostgres,
    ListTuistPostgresTables,
    DescribeTuistPostgresTable,
    QueryTuistClickhouse,
    ListTuistClickhouseTables,
    DescribeTuistClickhouseTable,
    ListAssets,
    GetAsset,
    ListAssetFinancings,
    ListAssetAssignments,
    ListAssetEvents,
    GetAssetBookValue,
    CreateAsset,
    AssignAsset,
    ReturnAsset,
    RetireAsset,
    DisposeAsset,
    RecordAssetRepair,
    RecordAssetIncident,
    RecordAssetNote,
    RecordAssetWarrantyExtension,
    MarkAssetReturnedToLessor,
    EditAssetMetadata,
    DeleteAsset,
    PlaceAssetInService,
    MarkAssetInRepair,
    MarkAssetRepaired,
    MarkAssetLost,
    RecoverAsset,
    ListDataCenters,
    GetDataCenter,
    CreateDataCenter,
    EditDataCenter,
    DecommissionDataCenter,
    DeleteDataCenter,
    InstallAssetInDataCenter,
    ListInsurancePolicies,
    GetInsurancePolicy,
    CreateInsurancePolicy,
    EditInsurancePolicy,
    ActivateInsurancePolicy,
    ExpireInsurancePolicy,
    CancelInsurancePolicy,
    DeleteInsurancePolicy,
    AddAssetToInsurance,
    RemoveAssetFromInsurance,
    EditInsuranceMember,
    RecordInsuranceClaim,
    UpdateInsuranceClaim,
    LinkAssetToInsuranceClaim,
    UnlinkAssetFromInsuranceClaim,
    AttachDocumentToInsurancePolicy,
    DetachDocumentFromInsurancePolicy,
    AttachDocumentToInsuranceClaim,
    DetachDocumentFromInsuranceClaim,
    ListFinancings,
    GetFinancing,
    CreateFinancing,
    EditFinancingMetadata,
    AttachDocumentToFinancing,
    DetachDocumentFromFinancing,
    DeleteFinancing,
    SetFinancingLines,
    SetFinancingAccountingTreatment,
    ImportFinancingSchedule,
    MatchFinancingPayment,
    EditFinancingPaymentDecomposition,
    MarkFinancingPaidOff,
    ExercisePurchaseOption,
    ReturnFinancing,
    TerminateFinancing
  ]

  def server do
    EMCP.Server.new(
      name: @name,
      version: @version,
      title: @title,
      description: @description,
      instructions: @instructions,
      tools: @static_tools,
      prompts: @prompts
    )
  end

  @doc "MCP protocol revisions this server can speak, newest first."
  def supported_protocol_versions, do: @supported_protocol_versions

  def handle_message(conn, raw) when is_binary(raw) do
    case JSON.decode(raw) do
      {:ok, request} -> handle_message(conn, request)
      {:error, _error} -> error_response(nil, -32_700, "Parse error")
    end
  end

  def handle_message(conn, %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => id}) do
    static_tools =
      @static_tools
      |> Enum.filter(&tool_allowed?(conn, &1))
      |> Enum.map(&Tool.descriptor/1)

    result_response(id, %{"tools" => static_tools ++ Proxy.list_hoisted_tools(conn)})
  end

  def handle_message(conn, %{"jsonrpc" => "2.0", "method" => "initialize", "id" => _id} = request) do
    negotiated = negotiated_protocol_version(request)

    case EMCP.Server.handle_message(server(), conn, request) do
      %{"result" => result} = response -> %{response | "result" => Map.put(result, "protocolVersion", negotiated)}
      response -> response
    end
  end

  def handle_message(
        conn,
        %{"jsonrpc" => "2.0", "method" => "tools/call", "id" => id, "params" => %{"name" => name} = params} = request
      ) do
    arguments = params["arguments"] || %{}

    if static_tool_allowed_by_name?(conn, name) do
      dispatch_tool_call(conn, request, id, name, arguments)
    else
      error_response(id, -32_603, "Tool #{name} is not available for this MCP session")
    end
  end

  def handle_message(conn, request) when is_map(request) do
    EMCP.Server.handle_message(server(), conn, request)
  end

  # A client that asks for a revision we do not speak still gets a usable session on
  # the newest one we do, which is what the specification prescribes for initialize.
  defp negotiated_protocol_version(%{"params" => %{"protocolVersion" => requested}})
       when requested in @supported_protocol_versions, do: requested

  defp negotiated_protocol_version(_request), do: @latest_protocol_version

  defp dispatch_tool_call(conn, request, id, name, arguments) do
    Audit.with_context(Audit.context_from_conn(conn), fn ->
      response =
        case Proxy.call_hoisted_tool(conn, name, arguments) do
          {:ok, result} -> result_response(id, result)
          {:error, message} -> error_response(id, -32_603, message)
          :not_proxy_tool -> EMCP.Server.handle_message(server(), conn, request)
        end

      log_tool_call(conn, name, arguments, response)
      response
    end)
  end

  defp tool_allowed?(conn, tool_module) do
    admin_tool_allowed?(conn, tool_module) and
      (not restricted_mcp_session?(conn) or tool_group(tool_module) in allowed_tool_groups(conn))
  end

  defp static_tool_allowed_by_name?(conn, name) do
    case Enum.find(@static_tools, &(tool_name(&1) == name)) do
      nil -> true
      tool_module -> tool_allowed?(conn, tool_module)
    end
  end

  defp tool_group(tool_module) when tool_module in @finance_tools, do: "finance"
  defp tool_group(tool_module) when tool_module in @document_tools, do: "documents"
  defp tool_group(tool_module) when tool_module in @contract_tools, do: "contracts"
  defp tool_group(tool_module) when tool_module in @admin_tools, do: "admin"
  defp tool_group(tool_module) when tool_module in @hardware_tools, do: "hardware"
  # The read-only Tuist database tools sit in the same "observability"
  # ("Production systems") group as the Grafana/ClickHouse proxy tools — same
  # gating, granted by the same identity toggle. They are not executive-only.
  defp tool_group(tool_module) when tool_module in @tuist_server_tools, do: "observability"
  defp tool_group(_tool_module), do: "default"

  defp admin_tool_allowed?(conn, tool_module) when tool_module in @admin_tools do
    conn
    |> Tool.current_user()
    |> Atlas.Users.has_scope?("admin:read")
  end

  defp admin_tool_allowed?(_conn, _tool_module), do: true

  defp log_tool_call(conn, name, arguments, response) do
    if Tool.current_user(conn) do
      Audit.record("mcp.tool_called", %{
        target_type: "mcp_tool",
        target_id: name,
        target_label: name,
        metadata:
          conn
          |> mcp_claim_metadata()
          |> Map.merge(%{
            arguments: arguments,
            status: tool_call_status(response)
          })
      })
    end
  end

  defp mcp_claim_metadata(%{assigns: %{mcp_claims: claims}}), do: Audit.claim_metadata(claims)
  defp mcp_claim_metadata(_conn), do: %{}

  defp tool_call_status(%{"error" => _error}), do: "error"
  defp tool_call_status(%{"result" => %{"isError" => true}}), do: "error"
  defp tool_call_status(_response), do: "ok"

  defp tool_name(tool_module), do: tool_module |> EMCP.Tool.to_map() |> Map.fetch!("name")

  defp restricted_mcp_session?(%{assigns: %{mcp_claims: %{"mcp_tool_groups" => groups}}}) when is_list(groups), do: true
  defp restricted_mcp_session?(_conn), do: false

  defp allowed_tool_groups(%{assigns: %{mcp_claims: %{"mcp_tool_groups" => groups}}}) when is_list(groups) do
    ["default" | Enum.map(groups, &to_string/1)]
  end

  defp allowed_tool_groups(_conn), do: ["default"]

  defp result_response(id, result), do: %{"jsonrpc" => "2.0", "id" => id, "result" => result}

  defp error_response(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
