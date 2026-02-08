//
//  CustomerDetailContent.swift
//  Whale
//
//  Customer detail, order detail, and order history views
//  for CustomerSearchContent.
//

import SwiftUI
import os.log

// MARK: - Full Screen Views

extension CustomerSearchContent {

    @ViewBuilder
    func customerDetailFullScreen(_ customer: Customer) -> some View {
        let displayCustomer = updatedCustomer ?? customer

        VStack(spacing: 0) {
            // Custom header with liquid glass back button
            HStack(spacing: 14) {
                Button {
                    Haptics.light()
                    if isEditingCustomer {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isEditingCustomer = false
                            editErrorMessage = nil
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            detailAppearAnimation = false
                            updatedCustomer = nil
                            mode = .search
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                        Text(isEditingCustomer ? "Cancel" : "Back")
                            .font(Design.Typography.subhead).fontWeight(.medium)
                    }
                    .foregroundStyle(Design.Colors.Text.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                if isEditingCustomer {
                    Button {
                        Haptics.medium()
                        Task { await saveCustomerEdits(for: customer) }
                    } label: {
                        HStack(spacing: 5) {
                            if isSavingCustomer {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(Design.Colors.Text.primary)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(Design.Typography.footnote).fontWeight(.semibold)
                            }
                            Text("Save")
                                .font(Design.Typography.subhead).fontWeight(.medium)
                        }
                        .foregroundStyle(Design.Colors.Text.primary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .disabled(isSavingCustomer)
                } else {
                    Button {
                        Haptics.light()
                        startEditingCustomer(displayCustomer)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                                .font(Design.Typography.footnote).fontWeight(.semibold)
                            Text("Edit")
                                .font(Design.Typography.subhead).fontWeight(.medium)
                        }
                        .foregroundStyle(Design.Colors.Text.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }

                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if isEditingCustomer {
                        customerEditContent(displayCustomer)
                    } else {
                        customerDetailContent(displayCustomer)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 34)
                .scaleEffect(detailAppearAnimation ? 1 : 0.96)
                .opacity(detailAppearAnimation ? 1 : 0)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                detailAppearAnimation = true
            }
        }
        .alert("Adjust Loyalty Points", isPresented: $showPointsAdjustment) {
            TextField("New total points", text: $pointsAdjustmentValue)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) {
                pointsAdjustmentValue = ""
                adjustingPointsForCustomer = nil
            }
            Button("Save") {
                applyPointsAdjustment()
            }
        } message: {
            if let customer = adjustingPointsForCustomer {
                Text("Current: \(customer.formattedLoyaltyPoints)\nEnter new total points value.")
            }
        }
        .overlay {
            if let message = pointsAdjustmentMessage {
                VStack {
                    Spacer()
                    Text(message)
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.green.opacity(0.9), in: Capsule())
                        .padding(.bottom, 100)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    Task { @MainActor in try? await Task.sleep(for: .seconds(2));
                        withAnimation { pointsAdjustmentMessage = nil }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func orderDetailFullScreen(order: Order, customer: Customer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mode = .detail(customer)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                        Text(customer.displayName)
                            .font(Design.Typography.subhead).fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Design.Colors.Text.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                Text("Order #\(order.shortOrderNumber)")
                    .font(Design.Typography.headline).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()

                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            OrderDetailContentView(
                order: order,
                showCustomerInfo: false,
                customerOverride: customer
            )
        }
    }

    func orderHistoryFullScreen(customer: Customer) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    Haptics.light()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        mode = .detail(customer)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(Design.Typography.footnote).fontWeight(.semibold)
                        Text(customer.displayName)
                            .font(Design.Typography.subhead).fontWeight(.medium)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Design.Colors.Text.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Capsule())

                Spacer()

                Text("Order History")
                    .font(Design.Typography.headline).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                Spacer()

                Button {
                    Haptics.light()
                    onDismiss()
                } label: {
                    Text("Done")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.disabled)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(Design.Typography.subhead).fontWeight(.medium)
                    .foregroundStyle(Design.Colors.Text.subtle)
                    .accessibilityHidden(true)

                TextField("Search orders...", text: $orderHistorySearchText)
                    .font(Design.Typography.subhead)
                    .foregroundStyle(Design.Colors.Text.primary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !orderHistorySearchText.isEmpty {
                    Button {
                        orderHistorySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(Design.Typography.callout)
                            .foregroundStyle(Design.Colors.Text.subtle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Design.Colors.Border.subtle, in: .rect(cornerRadius: 12))
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if isLoadingFullHistory {
                Spacer()
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Design.Colors.Text.disabled)
                Spacer()
            } else if filteredOrderHistory.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: orderHistorySearchText.isEmpty ? "bag" : "magnifyingglass")
                        .font(Design.Typography.largeTitle).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.ghost)
                        .accessibilityHidden(true)
                    Text(orderHistorySearchText.isEmpty ? "No orders yet" : "No matching orders")
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.subtle)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredOrderHistory.enumerated()), id: \.element.id) { index, order in
                            OrderRowCompact(order: order) {
                                Haptics.light()
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    mode = .orderDetail(order, customer)
                                }
                            }

                            if index < filteredOrderHistory.count - 1 {
                                Divider()
                                    .background(Design.Colors.Border.regular)
                                    .padding(.horizontal, 14)
                            }
                        }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
                .contentMargins(.vertical, 1, for: .scrollContent)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            loadFullOrderHistory(for: customer)
        }
    }

    var filteredOrderHistory: [Order] {
        guard !orderHistorySearchText.isEmpty else { return fullOrderHistory }
        let query = orderHistorySearchText.lowercased()
        return fullOrderHistory.filter { order in
            order.orderNumber.lowercased().contains(query) ||
            order.formattedTotal.lowercased().contains(query) ||
            order.status.displayName.lowercased().contains(query) ||
            order.formattedDate.lowercased().contains(query)
        }
    }

    func loadFullOrderHistory(for customer: Customer) {
        guard fullOrderHistory.isEmpty else { return }
        isLoadingFullHistory = true
        Task {
            do {
                let orders = try await OrderService.fetchOrdersForCustomer(
                    customerId: customer.id,
                    storeId: storeId,
                    limit: 100
                )
                await MainActor.run {
                    fullOrderHistory = orders
                    isLoadingFullHistory = false
                }
            } catch {
                Log.network.error("Failed to load full order history: \(error)")
                await MainActor.run {
                    fullOrderHistory = []
                    isLoadingFullHistory = false
                }
            }
        }
    }
}

// MARK: - Customer Detail Sections

extension CustomerSearchContent {

    @ViewBuilder
    func customerDetailContent(_ customer: Customer) -> some View {
        customerProfileCard(customer)
        customerCRMStats(customer)
        customerContactSection(customer)
        customerOrdersSection(customer)

        Button {
            Haptics.medium()
            selectCustomer(updatedCustomer ?? customer)
        } label: {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(Design.Typography.headline).fontWeight(.semibold)
                Text("Select Customer")
                    .font(Design.Typography.callout).fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Design.Colors.Semantic.accent, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            loadCustomerOrders(for: customer)
        }
    }

    @ViewBuilder
    func customerEditContent(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(Design.Typography.caption1).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.disabled)
                .tracking(0.5)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    TextField("", text: $editFirstName, prompt: Text("First").foregroundColor(Design.Colors.Text.placeholder))
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))

                HStack(spacing: 12) {
                    TextField("", text: $editLastName, prompt: Text("Last").foregroundColor(Design.Colors.Text.placeholder))
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("CONTACT INFORMATION")
                .font(Design.Typography.caption1).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.disabled)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.subtle)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    TextField("", text: $editPhone, prompt: Text("Phone").foregroundColor(Design.Colors.Text.placeholder))
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.phonePad)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(Design.Colors.Border.regular)

                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.subtle)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    TextField("", text: $editEmail, prompt: Text("Email").foregroundColor(Design.Colors.Text.placeholder))
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().background(Design.Colors.Border.regular)

                HStack(spacing: 12) {
                    Image(systemName: "calendar")
                        .font(Design.Typography.footnote).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.subtle)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    TextField("", text: $editDateOfBirth, prompt: Text("MM/DD/YYYY").foregroundColor(Design.Colors.Text.placeholder))
                        .font(Design.Typography.subhead).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.primary)
                        .keyboardType(.numbersAndPunctuation)
                        .onChange(of: editDateOfBirth) { _, newValue in
                            editDateOfBirth = formatDateInput(newValue)
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 14))
        }

        if let error = editErrorMessage {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Design.Typography.subhead)
                    .accessibilityHidden(true)
                Text(error)
                    .font(Design.Typography.footnote).fontWeight(.medium)
            }
            .foregroundStyle(Design.Colors.Semantic.error)
            .accessibilityElement(children: .combine)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14).fill(Design.Colors.Semantic.error.opacity(0.1)))
        }

        Text("Tap Save to update customer information")
            .font(Design.Typography.footnote).fontWeight(.medium)
            .foregroundStyle(Design.Colors.Text.subtle)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
    }

    func startEditingCustomer(_ customer: Customer) {
        editFirstName = customer.firstName ?? ""
        editLastName = customer.lastName ?? ""
        editEmail = customer.email ?? ""
        editPhone = customer.phone ?? ""

        if let dob = customer.dateOfBirth, !dob.isEmpty {
            let inputFormatter = DateFormatter()
            inputFormatter.dateFormat = "yyyy-MM-dd"
            if let date = inputFormatter.date(from: dob) {
                let outputFormatter = DateFormatter()
                outputFormatter.dateFormat = "MM/dd/yyyy"
                editDateOfBirth = outputFormatter.string(from: date)
            } else {
                editDateOfBirth = ""
            }
        } else {
            editDateOfBirth = ""
        }

        editErrorMessage = nil
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isEditingCustomer = true
        }
    }

    func saveCustomerEdits(for customer: Customer) async {
        editErrorMessage = nil
        isSavingCustomer = true
        defer { isSavingCustomer = false }

        let trimmedFirst = editFirstName.trimmingCharacters(in: .whitespaces)
        let trimmedLast = editLastName.trimmingCharacters(in: .whitespaces)

        if trimmedFirst.isEmpty || trimmedLast.isEmpty {
            editErrorMessage = "First and last name are required"
            return
        }

        var dobFormatted: String? = nil
        if !editDateOfBirth.isEmpty {
            guard let parsed = parseDate(editDateOfBirth) else {
                editErrorMessage = "Invalid date format (use MM/DD/YYYY)"
                return
            }
            dobFormatted = parsed
        }

        let fields = CustomerUpdateFields(
            firstName: trimmedFirst,
            lastName: trimmedLast,
            email: editEmail.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editEmail.trimmingCharacters(in: .whitespaces),
            phone: editPhone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : editPhone.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dobFormatted
        )

        let result = await CustomerService.updateCustomer(customer.id, fields: fields)

        await MainActor.run {
            switch result {
            case .success(let updated):
                Log.network.info("Customer updated: \(updated.displayName)")
                updatedCustomer = updated
                Haptics.success()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isEditingCustomer = false
                    pointsAdjustmentMessage = "Customer updated successfully"
                }
            case .failure(let error):
                Log.network.error("Customer update failed: \(error)")
                editErrorMessage = "Update failed: \(error.localizedDescription)"
                Haptics.error()
            }
        }
    }

    func customerProfileCard(_ customer: Customer) -> some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Design.Colors.Glass.thick)
                    .frame(width: 72, height: 72)

                Text(customer.initials)
                    .font(Design.Typography.title2).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.secondary)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(customer.displayName)
                    .font(Design.Typography.title2).fontWeight(.bold)
                    .foregroundStyle(Design.Colors.Text.primary)

                HStack(spacing: 12) {
                    HStack(spacing: 5) {
                        Image(systemName: "crown.fill")
                            .font(Design.Typography.caption2).fontWeight(.bold)
                            .accessibilityHidden(true)
                        Text(customer.loyaltyTierDisplay)
                            .font(Design.Typography.caption1).fontWeight(.bold)
                    }
                    .foregroundStyle(Design.Colors.Text.quaternary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Design.Colors.Glass.thick, in: .capsule)

                    Text("Since \(formatMemberSince(customer.createdAt))")
                        .font(Design.Typography.caption1).fontWeight(.medium)
                        .foregroundStyle(Design.Colors.Text.subtle)
                }
            }

            Spacer()
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    func customerCRMStats(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("METRICS")
                .font(Design.Typography.caption1).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.disabled)
                .tracking(0.5)
                .padding(.leading, 4)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                CRMStatBox(
                    title: "Lifetime Value",
                    value: formatCurrency(customer.totalSpent ?? 0),
                    icon: "dollarsign.circle.fill"
                )

                CRMStatBox(
                    title: "Total Orders",
                    value: "\(customer.totalOrders ?? 0)",
                    icon: "bag.fill"
                )

                EditableLoyaltyStatBox(
                    value: displayLoyaltyPoints(for: customer),
                    isAdjusting: isAdjustingPoints && adjustingPointsForCustomer?.id == customer.id
                ) {
                    Haptics.medium()
                    adjustingPointsForCustomer = customer
                    pointsAdjustmentValue = ""
                    updatedLoyaltyPoints = nil
                    showPointsAdjustment = true
                }

                CRMStatBox(
                    title: "Avg. Order",
                    value: formatAverageOrder(totalSpent: customer.totalSpent, orderCount: customer.totalOrders),
                    icon: "chart.bar.fill"
                )
            }
        }
    }

    func customerContactSection(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CONTACT INFORMATION")
                .font(Design.Typography.caption1).fontWeight(.semibold)
                .foregroundStyle(Design.Colors.Text.disabled)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 1) {
                if let phone = customer.formattedPhone {
                    ContactInfoRow(icon: "phone.fill", label: "Phone", value: phone)
                }
                if let email = customer.email, !email.isEmpty {
                    ContactInfoRow(icon: "envelope.fill", label: "Email", value: email)
                }
                if let dob = customer.dateOfBirth, !dob.isEmpty {
                    ContactInfoRow(icon: "calendar", label: "Date of Birth", value: formatDOBWithAge(dob))
                }
                if let address = customer.formattedAddress {
                    ContactInfoRow(icon: "location.fill", label: "Address", value: address)
                }

                if customer.formattedPhone == nil && (customer.email ?? "").isEmpty {
                    HStack {
                        Spacer()
                        Text("No contact info on file")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.placeholder)
                        Spacer()
                    }
                    .padding(.vertical, 16)
                }
            }
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
        }
    }

    func customerOrdersSection(_ customer: Customer) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("RECENT ORDERS")
                    .font(Design.Typography.caption1).fontWeight(.semibold)
                    .foregroundStyle(Design.Colors.Text.disabled)
                    .tracking(0.5)

                Spacer()

                if isLoadingOrders {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(Design.Colors.Text.subtle)
                } else if customerOrders.count > 0 {
                    Button {
                        Haptics.light()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            mode = .orderHistory(customer)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("See All")
                                .font(Design.Typography.footnote).fontWeight(.medium)
                            Image(systemName: "chevron.right")
                                .font(Design.Typography.caption2).fontWeight(.semibold)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(Design.Colors.Text.disabled)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all orders")
                }
            }
            .padding(.leading, 4)

            if customerOrders.isEmpty && !isLoadingOrders {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "bag")
                            .font(Design.Typography.title2).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.ghost)
                            .accessibilityHidden(true)
                        Text("No order history")
                            .font(Design.Typography.footnote).fontWeight(.medium)
                            .foregroundStyle(Design.Colors.Text.placeholder)
                    }
                    .padding(.vertical, 28)
                    Spacer()
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(customerOrders.prefix(3).enumerated()), id: \.element.id) { index, order in
                        OrderRowCompact(order: order) {
                            Haptics.light()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                mode = .orderDetail(order, customer)
                            }
                        }

                        if index < min(customerOrders.count, 3) - 1 {
                            Divider()
                                .background(Design.Colors.Border.regular)
                                .padding(.horizontal, 14)
                        }
                    }
                }
                .glassEffect(.regular, in: .rect(cornerRadius: 14))
            }
        }
    }

    func loadCustomerOrders(for customer: Customer) {
        isLoadingOrders = true
        Task {
            do {
                let orders = try await OrderService.fetchOrdersForCustomer(customerId: customer.id, storeId: storeId, limit: 5)
                await MainActor.run {
                    customerOrders = orders
                    isLoadingOrders = false
                }
            } catch {
                Log.network.error("Failed to load customer orders: \(error)")
                await MainActor.run {
                    customerOrders = []
                    isLoadingOrders = false
                }
            }
        }
    }
}

// MARK: - Loyalty Points

extension CustomerSearchContent {

    func applyPointsAdjustment() {
        guard let customer = adjustingPointsForCustomer,
              let newPoints = Int(pointsAdjustmentValue.trimmingCharacters(in: .whitespaces)),
              newPoints >= 0 else {
            pointsAdjustmentValue = ""
            adjustingPointsForCustomer = nil
            return
        }

        isAdjustingPoints = true
        pointsAdjustmentValue = ""

        Task {
            do {
                Log.network.debug("Adjusting points for customer \(customer.id) to \(newPoints)")
                let result = try await LoyaltyService.shared.setPoints(
                    customerId: customer.id,
                    points: newPoints,
                    reason: "staff_adjustment"
                )

                await MainActor.run {
                    Log.network.info("Points adjustment succeeded: \(result.balanceBefore ?? 0) -> \(result.balanceAfter ?? 0)")
                    updatedLoyaltyPoints = result.balanceAfter ?? newPoints
                    isAdjustingPoints = false
                    adjustingPointsForCustomer = nil

                    let message: String
                    if let adjustment = result.adjustment, adjustment != 0 {
                        let sign = adjustment > 0 ? "+" : ""
                        message = "Points: \(result.balanceBefore ?? 0) → \(result.balanceAfter ?? 0) (\(sign)\(adjustment))"
                    } else {
                        message = result.message ?? "Points updated"
                    }
                    withAnimation {
                        pointsAdjustmentMessage = message
                    }
                    Haptics.success()
                }
            } catch {
                Log.network.error("Points adjustment failed: \(error)")
                await MainActor.run {
                    isAdjustingPoints = false
                    adjustingPointsForCustomer = nil
                    withAnimation {
                        pointsAdjustmentMessage = "Failed: \(error.localizedDescription)"
                    }
                    Haptics.error()
                }
            }
        }
    }

    func displayLoyaltyPoints(for customer: Customer) -> String {
        if let override = updatedLoyaltyPoints, adjustingPointsForCustomer == nil {
            if case .detail(let currentCustomer) = mode, currentCustomer.id == customer.id {
                return "\(override)"
            }
        }
        return customer.formattedLoyaltyPoints
    }

    func formatDOBWithAge(_ dateString: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        guard let date = inputFormatter.date(from: dateString) else {
            return dateString
        }
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "MMM d, yyyy"
        let formatted = outputFormatter.string(from: date)

        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: date, to: Date())
        if let age = ageComponents.year {
            return "\(formatted) (\(age) yrs)"
        }
        return formatted
    }

    func formatMemberSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }

    func formatAverageOrder(totalSpent: Decimal?, orderCount: Int?) -> String {
        guard let spent = totalSpent, let count = orderCount, count > 0 else { return "$0" }
        let average = spent / Decimal(count)
        return formatCurrency(average)
    }
}
