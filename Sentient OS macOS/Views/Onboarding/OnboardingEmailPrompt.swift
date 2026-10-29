// OnboardingEmailPrompt.swift
// Required email entry when onboarding reaches the source picker, as a Setup Assistant field
// page. submit() validates the address; a durable enqueue is followed by an optional company
// welcome before source selection.
// Doc: Documentation - Onboarding.md

import SwiftUI

struct OnboardingEmailPrompt: View {
    let onSaved: () -> Void

    @State private var email = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var welcome: YCCompanyWelcome?
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.sidekickReduceMotionOverride) private var motionOverride
    @FocusState private var emailFocused: Bool

    private var motion: Animation? {
        Motion.gated(Motion.standard, reduceMotion: motionOverride ?? systemReduced)
    }

    var body: some View {
        Group {
            if let welcome {
                OnboardingCompanyWelcome(company: welcome, onContinue: onSaved)
                    .transition(.opacity)
            } else {
                emailForm.transition(.opacity)
            }
        }
        // A sheet sizes itself to an ideal size; the page's ScrollView has none of its own.
        .frame(minWidth: 460, idealWidth: 560, minHeight: 420, idealHeight: 520)
        .interactiveDismissDisabled()
        .task(id: isSaving) {
            guard isSaving, welcome == nil, let address = MailAccount.normalizedEmail(email) else { return }
            do {
                try await MailAccountCloud.onboarding.enqueue([address])
                let match = await YCWelcomeClient.shared.lookup(email: address)
                guard !Task.isCancelled else { return }
                if let match {
                    emailFocused = false
                    withAnimation(motion) { welcome = match }
                } else {
                    onSaved()
                }
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = "Your email couldn’t be saved on this Mac. Please try again."
                isSaving = false
                emailFocused = true
            }
        }
    }

    private var emailForm: some View {
        SetupAssistantPage(tile: .invitations, title: "What’s Your Email?",
                           message: "Your email is saved for occasional feedback invitations.") {
            VStack(alignment: .leading, spacing: Space.s) {
                TextField("Email address", text: $email, prompt: Text(verbatim: "you@example.com"))
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .focused($emailFocused)
                    .disabled(isSaving)
                    .accessibilityLabel("Email address")
                    .onSubmit(submit)
                    .onChange(of: email) { errorMessage = nil }

                if let errorMessage {
                    StatusLabel(errorMessage, tone: .error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } footer: {
            SetupAssistantFooter(primaryTitle: isSaving ? "Saving…" : "Save & Continue",
                                 primaryEnabled: !isSaving && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                 primary: submit)
        }
        .onAppear {
            if email.isEmpty { email = InviteProgram.shared.snapshot?.lateUse?.email ?? "" }
            emailFocused = true
        }
    }

    private func submit() {
        guard !isSaving else { return }
        guard MailAccount.normalizedEmail(email) != nil else {
            errorMessage = "Enter a valid email address to continue."
            emailFocused = true
            return
        }
        errorMessage = nil
        isSaving = true
    }
}

#if DEBUG
#Preview("Onboarding email") {
    HStack(spacing: 0) {
        ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
            OnboardingEmailPrompt(onSaved: {})
                .frame(width: 720, height: 560)
                .background(.background)
                .environment(\.colorScheme, scheme)
        }
    }
}
#endif
