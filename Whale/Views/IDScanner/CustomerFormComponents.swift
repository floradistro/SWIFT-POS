//
//  CustomerFormComponents.swift
//  Whale
//
//  Customer creation form, scanner content, and shared helpers
//  for CustomerSearchContent.
//

import SwiftUI
import UIKit

// MARK: - Create Content

extension CustomerSearchContent {

    @ViewBuilder
    var createContent: some View {
        // Name fields
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("", text: $firstName, prompt: Text("First").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($focusedCreateField, equals: .firstName)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                HStack(spacing: 12) {
                    TextField("", text: $lastName, prompt: Text("Last").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($focusedCreateField, equals: .lastName)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
        }

        // DOB
        VStack(alignment: .leading, spacing: 8) {
            Text("DATE OF BIRTH")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
                TextField("", text: $dateOfBirth, prompt: Text("MM/DD/YYYY").foregroundColor(.white.opacity(0.35)))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .keyboardType(.numbersAndPunctuation)
                    .focused($focusedCreateField, equals: .dob)
                    .onChange(of: dateOfBirth) { _, newValue in
                        dateOfBirth = formatDateInput(newValue)
                    }
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }

        // Contact
        VStack(alignment: .leading, spacing: 8) {
            Text("CONTACT (OPTIONAL)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $phone, prompt: Text("Phone").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.phonePad)
                        .focused($focusedCreateField, equals: .phone)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(.white.opacity(0.08))

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(width: 20)
                    TextField("", text: $email, prompt: Text("Email").foregroundColor(.white.opacity(0.35)))
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .focused($focusedCreateField, equals: .email)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }

        // Error
        if let error = errorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                Text(error)
                    .font(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Colors.Semantic.error.opacity(0.1)))
        }

        // Create button
        Button {
            Haptics.medium()
            focusedCreateField = nil
            Task { await createCustomer() }
        } label: {
            HStack {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.white)
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Create Customer")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(isCreateValid ? .white : .white.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(.white.opacity(isCreateValid ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(!isCreateValid || isCreating)
    }

    @ViewBuilder
    var scannerContent: some View {
        VStack(spacing: 20) {
            ZStack {
                ProgressView()
                    .scaleEffect(1.3)
                    .tint(.white.opacity(0.6))
            }
            .frame(width: 80, height: 80)
            .background(Circle().fill(.white.opacity(0.08)))

            Text("Launching scanner...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.04)))
        .onAppear {
            showFullScreenScanner = true
        }
        .fullScreenCover(isPresented: $showFullScreenScanner) {
            IDScannerView(
                storeId: storeId,
                onCustomerSelected: { customer in
                    showFullScreenScanner = false
                    selectCustomer(customer)
                },
                onDismiss: {
                    showFullScreenScanner = false
                    mode = .search
                },
                onScannedIDWithMatches: { scannedID, matches in
                    showFullScreenScanner = false
                    localScannedID = scannedID
                    localScannedMatches = matches
                    mode = .search
                    print("🆔 Scanner returned to sheet - name: \(scannedID.fullDisplayName), matches: \(matches.count)")
                }
            )
        }
    }
}

// MARK: - Helpers

extension CustomerSearchContent {

    var displayName: String {
        let first = firstName.trimmingCharacters(in: .whitespaces)
        let last = lastName.trimmingCharacters(in: .whitespaces)
        if first.isEmpty && last.isEmpty { return "" }
        return "\(first) \(last)".trimmingCharacters(in: .whitespaces)
    }

    var isCreateValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func selectCustomer(_ customer: Customer) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil, from: nil, for: nil
        )

        Haptics.success()
        onCustomerCreated(customer)
    }

    func formatDateInput(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(8))

        var result = ""
        for (index, char) in limited.enumerated() {
            if index == 2 || index == 4 { result += "/" }
            result.append(char)
        }
        return result
    }

    func parseDate(_ dateString: String) -> String? {
        let parts = dateString.split(separator: "/")
        guard parts.count == 3,
              let month = Int(parts[0]), month >= 1, month <= 12,
              let day = Int(parts[1]), day >= 1, day <= 31,
              let year = Int(parts[2]), year >= 1900, year <= 2100 else {
            return nil
        }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: value as NSDecimalNumber) ?? "$0.00"
    }

    func createCustomer() async {
        errorMessage = nil
        isCreating = true
        defer { isCreating = false }

        var dobFormatted: String? = nil
        if !dateOfBirth.isEmpty {
            guard let parsed = parseDate(dateOfBirth) else {
                errorMessage = "Invalid date format"
                return
            }
            dobFormatted = parsed
        }

        let scanned = effectiveScannedID

        let customerData = NewCustomerFromScan(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            middleName: scanned?.middleName,
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dobFormatted,
            streetAddress: scanned?.streetAddress,
            city: scanned?.city,
            state: scanned?.state,
            postalCode: scanned?.zipCode,
            driversLicenseNumber: scanned?.licenseNumber
        )

        let phoneValue = phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone
        let emailValue = email.trimmingCharacters(in: .whitespaces).isEmpty ? nil : email

        let result = await CustomerService.createCustomer(customerData, storeId: storeId, phone: phoneValue, email: emailValue)

        switch result {
        case .success(let customer):
            Haptics.success()
            onCustomerCreated(customer)
        case .failure(let error):
            Haptics.error()
            errorMessage = error.localizedDescription
        }
    }

    func performSearch(query: String) {
        searchTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            searchResults = []
            isSearching = false
            return
        }

        isSearching = true

        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }

            let results = await CustomerService.searchCustomers(
                query: trimmed,
                storeId: storeId,
                limit: 10
            )

            guard !Task.isCancelled else { return }

            await MainActor.run {
                searchResults = results
                isSearching = false
            }
        }
    }

    func selectScannedMatch(_ match: CustomerMatch) {
        if match.customer.driversLicenseNumber == nil, let scanned = effectiveScannedID, let license = scanned.licenseNumber {
            Task { await CustomerService.updateCustomerLicense(match.customer.id, licenseNumber: license) }
        }

        ScanFeedback.shared.customerFound()
        onCustomerCreated(match.customer)
    }

    func prefillCreateFormFromScan() {
        guard let scanned = effectiveScannedID else { return }
        firstName = scanned.firstName ?? ""
        lastName = scanned.lastName ?? ""
        if let dob = scanned.dateOfBirth {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM-dd"
            if let date = inputFormatter.date(from: dob) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MM/dd/yyyy"
                dateOfBirth = outputFormatter.string(from: date)
            }
        }
    }
}
