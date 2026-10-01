//
//  VoticeManager.swift
//  openclient-llm
//
//  Created by Arturo Carretero Calvo on 30/03/2026.
//  Copyright © 2026 ArtCC. All rights reserved.
//

import Foundation
import VoticeSDK

@MainActor
protocol VoticeManagerProtocol: Sendable {
    func isConfigured() -> Bool
    func configure(_ userIsPremium: Bool) throws
}

final class VoticeManager: VoticeManagerProtocol {
    // MARK: - Public functions

    func isConfigured() -> Bool {
        Votice.isConfigured
    }

    func configure(_ userIsPremium: Bool) throws {
        let info = Bundle.main.infoDictionary
        let apiKey = info?["VOTICE_API_KEY"] as? String ?? ""
        let apiSecret = info?["VOTICE_API_SECRET"] as? String ?? ""
        let appId = info?["VOTICE_APP_ID"] as? String ?? ""
        do {
            try Votice.configure(
                apiKey: apiKey,
                apiSecret: apiSecret,
                appId: appId
            )

            let poppinsConfig = VoticeFontConfiguration(
                fontFamily: "Poppins",
                weights: [
                    .light: "Poppins-Light",
                    .regular: "Poppins-Regular",
                    .medium: "Poppins-Medium",
                    .semiBold: "Poppins-SemiBold",
                    .bold: "Poppins-Bold"
                ]
            )
            Votice.setFonts(poppinsConfig)
            Votice.setTexts(VoticeTexts())
            Votice.setDebugLogging(enabled: false)
            Votice.setCommentIsEnabled(enabled: true)
            Votice.setShowCompletedSeparately(enabled: false)
            Votice.setVisibleOptionalStatuses(accepted: true, blocked: true, rejected: true)
            Votice.setUserIsPremium(isPremium: false)
            Votice.setLiquidGlassEnabled(true)
        } catch {
            throw error
        }
    }
}

// MARK: - VoticeTextsProtocol

// swiftlint:disable identifier_name
struct VoticeTexts: VoticeTextsProtocol {
    // MARK: - General

    let cancel = String(localized: "Cancel")
    let error = String(localized: "Error")
    let ok = String(localized: "Ok")
    let submit = String(localized: "Submit")
    let optional = String(localized: "Optional")
    let success = String(localized: "Success")
    let warning = String(localized: "Warning")
    let info = String(localized: "Information")
    let genericError = String(localized: "Something went wrong. Please try again.")
    let anonymous = String(localized: "Anonymous")

    // MARK: - Suggestion List

    let loadingSuggestions = String(localized: "Loading suggestions...")
    let noSuggestionsYet = String(localized: "No suggestions yet.")
    let beFirstToSuggest = String(localized: "Be the first to suggest something!")
    let noMatchingSuggestions = String(localized: "No matching suggestions")
    let noMatchingSuggestionsMessage = String(localized: "There are no suggestions for the selected status.")
    let noSuggestionsMessage = String(localized: "Suggestions will appear here when available.")
    let featureRequests = String(localized: "Suggestions")
    let all = String(localized: "All")
    let activeTab = String(localized: "Only active")
    let completedTab = String(localized: "Only completed")
    let pending = String(localized: "Pending")
    let accepted = String(localized: "Accepted")
    let blocked = String(localized: "Blocked")
    let inProgress = String(localized: "In Progress")
    let completed = String(localized: "Completed")
    let rejected = String(localized: "Rejected")
    let tapPlusToGetStarted = String(localized: "Tap + to get started")
    let loadingMore = String(localized: "Loading more...")

    // MARK: - Suggestion Detail

    let suggestionTitle = String(localized: "Suggestion")
    let issueTitle = String(localized: "Issue")
    let close = String(localized: "Close")
    let deleteSuggestionTitle = String(localized: "Delete suggestion")
    let deleteSuggestionMessage = String(localized: "Are you sure you want to delete this suggestion?")
    let delete = String(localized: "Delete")
    let suggestedBy = String(localized: "Suggested by")
    let suggestedAnonymously = String(localized: "Suggested anonymously")
    let votes = String(localized: "votes")
    let comments = String(localized: "comments")
    let commentsSection = String(localized: "Comments")
    let loadingComments = String(localized: "Loading comments...")
    let noComments = String(localized: "No comments yet. Be the first to comment!")
    let addComment = String(localized: "Add a comment")
    let yourComment = String(localized: "Your comment")
    let shareYourThoughts = String(localized: "Share your thoughts...")
    let yourNameOptional = String(localized: "Your name (optional)")
    let enterYourName = String(localized: "Enter your name")
    let newComment = String(localized: "New comment")
    let post = String(localized: "Post")
    let deleteCommentTitle = String(localized: "Delete comment")
    let deleteCommentMessage = String(localized: "Are you sure you want to delete this comment?")
    let deleteCommentPrimary = String(localized: "Delete")

    // MARK: - Create Suggestion

    let newSuggestion = String(localized: "New suggestion")
    let shareYourIdea = String(localized: "Share your idea")
    let helpUsImprove = String(localized: "Help us improve by suggesting new features or improvements.")
    let title = String(localized: "Title (Minimum 3 characters)")
    let titlePlaceholder = String(localized: "Enter a brief title for your suggestion")
    let keepItShort = String(localized: "Keep it short and descriptive")
    let descriptionOptional = String(localized: "Description (optional)")
    let descriptionPlaceholder = String(localized: "Describe your suggestion in detail...")
    let explainWhyUseful = String(localized: "Explain why this feature would be useful")
    let yourNameOptionalCreate = String(localized: "Your name (optional)")
    let enterYourNameCreate = String(localized: "Enter your name")
    let leaveEmptyAnonymous = String(localized: "Leave empty to submit anonymously")

    // MARK: - Create Issue (optional feature)

    let reportIssue = String(localized: "Report Issue")
    let reportIssueSubtitle = String(localized: "Help us fix it by describing the issue you encountered.")
    let titleIssuePlaceholder = String(localized: "Enter a brief title for the issue")
    let descriptionIssuePlaceholder = String(localized: "Describe the issue in detail...")
    let attachImage = String(localized: "Attach Image")
    let titleIssueImage = String(localized: "Issue Image")
    let loadingImage = String(localized: "Loading image...")
    let dragAndDropImage = String(localized: "Drag image here")
    let or = String(localized: "or")
}
// swiftlint:enable identifier_name
