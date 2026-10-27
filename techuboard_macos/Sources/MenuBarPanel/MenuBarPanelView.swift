import AppKit
import CoreImage
import SwiftUI

struct HistoryDeleteConfirmation: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let onConfirm: () -> Void
}

struct MenuBarPanelView: View {
    @ObservedObject var model: MenuBarPanelModel
    @ObservedObject var overflow: MenuBarOverflowManager
    @ObservedObject private var keepAwake = KeepAwakeManager.shared
    @ObservedObject private var notificationPopups = NotificationPopupPreference.shared
    @ObservedObject private var tokenManager = TokenUsageManager.shared
    @EnvironmentObject private var language: AppLanguageObserver
    @State private var showingLastIcon = false
    @State private var refreshingDevices = false
    @State private var imageAutoDelete = PreferencesManager.shared.isImageAutoDeleteEnabled
    @State private var imageDeleteLimit = PreferencesManager.shared.imageAutoDeleteThreshold
    @State private var launchAtLogin = LaunchAtLoginManager.isEnabled
    @State private var clipboardHistoryLimit = PreferencesManager.shared.historyLimit
    @State private var syncEnabled = PreferencesManager.shared.isSyncEnabled
    @State private var autoImageSync = PreferencesManager.shared.isAutoImageSyncEnabled
    @State private var isAvroInstalled = TechuAvroInstaller.isInstalled()
    @State private var isAvroWorking = false
    @State private var showClearHistoryConfirm = false
    @ObservedObject private var relayGroups = SyncRelayGroups.shared
    @ObservedObject private var updater = MacAppUpdater.shared
    @State private var deviceTabMode: Int = 0
    @State private var copiedPairingPin = false
    @State private var showPairingCard = false
    @State private var deleteConfirmTarget: HistoryDeleteConfirmation? = nil
    var activateIcon: (MenuBarOverflowItem) -> Void

    var body: some View {
        let _ = language.revision
        VStack(spacing: 0) {
            if updater.hasUpdate {
                updateAlertBanner
            }
            if let entry = model.savingSnippetEntry {
                MenuBarPanelSaveSnippetView(entry: entry, model: model)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                if model.page == .home {
                    topBar.padding(.bottom, 8)
                    tabs.padding(.bottom, 10)
                } else {
                    detailHeader.padding(.bottom, 10)
                }
                // The builder emits a detail header AND its body. Frame the stack,
                // not each emitted child, or the header consumes half the free height.
                VStack(spacing: 0) {
                    content
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 16).padding(.top, 14)
        .padding(.bottom, 12)
        .macGlassSurface(cornerRadius: 16)
        .overlay(alignment: .bottom) {
            if let notice = model.notice {
                Text(notice)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, y: 3)
                    .padding(.bottom, 52)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if let target = deleteConfirmTarget {
                deleteConfirmationDialogView(target)
            }
        }
        .font(AppFont.body).tint(AppColor.accent)
    }
    private var topBar: some View {
        HStack(spacing: 8) {
            // Left: Techuboard brand logo
            HStack(spacing: 6) {
                if let iconURL = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png") ?? Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
                   let nsImage = NSImage(contentsOf: iconURL) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 17, height: 13)
                        .foregroundStyle(AppColor.accent)
                } else {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.accent)
                }
                Text("Techuboard")
                    .font(.system(size: 13.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.primary)
            }
            .padding(.trailing, 2)

            search.frame(maxWidth: .infinity)

            Button {
                model.navigate(model.page == .settings ? .home : .settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(model.page == .settings ? AppColor.accent : Color.secondary)
                    .frame(width: 32, height: 32)
                    .background(model.page == .settings ? AppColor.accent.opacity(0.12) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(model.page == .settings ? 0.15 : 0.05), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(L10n.t(.preferences))
        }
    }
    private var detailHeader: some View {
        HStack(spacing: 8) {
            Button { model.navigate(.home) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text(L10n.t(.panelBack)).font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(AppColor.accent)
            Text(pageTitle).font(.system(size: 13, weight: .bold)).lineLimit(1)
            Spacer(minLength: 0)
        }.frame(height: 32)
    }
    private var updateAlertBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update Required: \(updater.latestVersion)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.white)
                Text("A new release is available to keep sync running smoothly.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
            Spacer()
            Button {
                if let urlStr = updater.downloadUrl, let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text("Update Now")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(colors: [Color.red.opacity(0.9), Color.orange.opacity(0.9)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.bottom, 8)
    }
    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.tertiary)
            MenuBarPanelSearchField(model: model)
            if model.isSearching {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Text("⌘F")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
        )
    }
    private var overflowStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t(.overflowTitle)).font(AppFont.caption).foregroundStyle(.secondary)
                Spacer()
                if overflow.status == .loading || overflow.status == .activating { ProgressView().controlSize(.small) }
            }
            if !overflow.items.isEmpty && overflow.enabled {
                ScrollViewReader { proxy in
                    HStack(spacing: 5) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 11) {
                                ForEach(overflow.items, id: \.id) { item in
                                    Button { activateIcon(item) } label: {
                                        HStack(spacing: 6) {
                                            if let image = item.image { Image(nsImage: image).resizable().scaledToFit().frame(width: 25, height: 25) }
                                            else { Image(systemName: "app.dashed").font(.system(size: 22)).frame(width: 25, height: 25) }
                                            Text(item.title).lineLimit(1).frame(maxWidth: 108, alignment: .leading)
                                        }.padding(.vertical, 2).contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(!item.canPress || overflow.status == .activating)
                                        .help(item.title + "\n" + L10n.t(item.canPress ? .overflowClickHint : .overflowUnavailable))
                                        .id(item.id)
                                }
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if overflow.items.count > 3 && !showingLastIcon {
                                LinearGradient(colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                                               startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 16).allowsHitTesting(false)
                            }
                        }
                        if overflow.items.count > 3 {
                            Button {
                                let target = showingLastIcon ? overflow.items.first?.id : overflow.items.last?.id
                                if let target {
                                    withAnimation(.easeOut(duration: 0.18)) {
                                        proxy.scrollTo(target, anchor: showingLastIcon ? .leading : .trailing)
                                    }
                                    showingLastIcon.toggle()
                                }
                            } label: {
                                Image(systemName: showingLastIcon ? "chevron.left" : "chevron.right")
                                    .font(AppFont.caption).frame(width: 24, height: 30)
                                    .contentShape(Rectangle())
                                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                                .help(L10n.t(showingLastIcon ? .overflowEarlierIcons : .overflowMoreIcons))
                                .accessibilityLabel(L10n.t(showingLastIcon ? .overflowEarlierIcons : .overflowMoreIcons))
                        }
                    }
                }.onChange(of: overflow.items.count) { _ in showingLastIcon = false }
                if overflow.status == .failed || overflow.status == .unconfirmed {
                    Text(L10n.t(overflow.status.messageKey)).font(AppFont.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 6) {
                    Text(L10n.t(overflow.status == .ready ? .overflowEmpty : overflow.status.messageKey))
                        .font(AppFont.secondary).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 4)
                    if !overflow.enabled { Button(L10n.t(.panelEnable)) { overflow.setEnabled(true) }.buttonStyle(.link) }
                    else if overflow.status == .needsPermission { Button(L10n.t(.overflowGrant)) { model.onAction?(.permission) }.buttonStyle(.link) }
                }.frame(minHeight: 21)
            }
        }.padding(10)
            .background(Color.primary.opacity(0.015), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
    private var tabs: some View {
        HStack(spacing: 3) {
            ForEach(MenuBarPanelModel.Tab.allCases, id: \.self) { tab in
                let isSelected = model.page == .home && model.tab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if tab == .clipboard && model.page == .home && model.tab == .clipboard {
                            model.cycleHistoryDeviceFilter()
                        } else {
                            model.selectTab(tab)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab == .clipboard ? model.clipboardTabIcon : tabIcon(tab))
                            .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        Text(tab == .devices ? L10n.format(.panelDeviceCount, model.devices.count) : (tab == .clipboard ? model.clipboardTabTitle : tab.title))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.06), radius: 3, x: 0, y: 1)
                            } else {
                                Color.clear
                            }
                        }
                    )
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func tabIcon(_ tab: MenuBarPanelModel.Tab) -> String {
        switch tab {
        case .clipboard: return "doc.on.clipboard"
        case .snippets: return "folder"
        case .devices: return "laptopcomputer.and.iphone"
        }
    }
    @ViewBuilder private var content: some View {
        switch model.page {
        case .home:
            if model.isSearching { searchResults }
            else {
                switch model.tab {
                case .clipboard: historyContent
                case .snippets: snippetsContent
                case .devices: devicesContent
                }
            }
        case .tools:
            ScrollViewReader { proxy in
                ScrollView { toolList }.onChange(of: model.selectedID) { id in if let id { proxy.scrollTo(id) } }
            }
        case .notifications: notificationsContent
        case .settings: settingsContent
        }
    }
    private var pageTitle: String {
        switch model.page {
        case .tools: return L10n.t(.menuTools)
        case .notifications: return L10n.t(.notificationSync)
        case .settings: return L10n.t(.preferences)
        case .home: return model.tab.title
        }
    }
    private var historyContent: some View {
        VStack(spacing: 4) {
            if model.deviceFilterMode == .noDevices {
                noDeviceConnectedCardsView
            } else {
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(HistoryTypeFilter.allCases) { filter in
                                filterPill(filter)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 1)
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            model.isSelectMode.toggle()
                            if !model.isSelectMode {
                                model.selectedIDs.removeAll()
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: model.isSelectMode ? "checkmark.circle.fill" : "checklist")
                                .font(.system(size: 10, weight: .semibold))
                            Text(model.isSelectMode ? "Done" : "Select")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            model.isSelectMode ? AppColor.accent.opacity(0.18) : Color.primary.opacity(0.04),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                model.isSelectMode ? AppColor.accent.opacity(0.4) : Color.primary.opacity(0.06),
                                lineWidth: 0.5
                            )
                        )
                        .foregroundStyle(model.isSelectMode ? AppColor.accent : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(model.isSelectMode ? "Exit selection mode" : "Select items to delete")
                }
                .padding(.bottom, 4)

                if model.isSelectMode {
                    selectionActionBar
                }

                historyList
                actionLink(.panelAllHistory) { model.onAction?(.search(model.query)) }
            }
        }
    }

    private var selectionActionBar: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.1)) {
                    model.selectAllVisible()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.selectedIDs.count == model.history.count && !model.history.isEmpty ? "checkmark.square.fill" : "square")
                        .font(.system(size: 11))
                    Text(model.selectedIDs.count == model.history.count && !model.history.isEmpty ? "Deselect All" : "Select All")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.primary.opacity(0.85))

            Text("(\(model.selectedIDs.count))")
                .font(.system(size: 10.5))
                .foregroundStyle(Color.secondary)

            Spacer()

            if !model.selectedIDs.isEmpty {
                Button {
                    let count = model.selectedIDs.count
                    deleteConfirmTarget = HistoryDeleteConfirmation(
                        title: "Delete \(count) Item\(count > 1 ? "s" : "")?",
                        message: "Are you sure you want to delete \(count) selected item\(count > 1 ? "s" : "") from clipboard history? This cannot be undone.",
                        onConfirm: {
                            model.deleteSelectedEntries()
                            model.notice = "Deleted \(count) item\(count > 1 ? "s" : "")"
                        }
                    )
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5))
                        Text("Delete (\(model.selectedIDs.count))")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }

            Button {
                deleteConfirmTarget = HistoryDeleteConfirmation(
                    title: "Clear All History?",
                    message: "Are you sure you want to clear all unpinned clipboard history? This cannot be undone.",
                    onConfirm: {
                        model.clearAllHistory()
                        model.notice = "History cleared"
                    }
                )
            } label: {
                Text("Clear All")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.red.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        .padding(.bottom, 2)
    }

    private var noDeviceConnectedCardsView: some View {
        VStack(spacing: 14) {
            VStack(spacing: 5) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.orange)
                Text("No Device Connected")
                    .font(.system(size: 13.5, weight: .bold))
                Text("Connect with your phone or PC to sync clipboard instantly:")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
            .padding(.top, 14)

            HStack(spacing: 10) {
                Button {
                    deviceTabMode = 0
                    showPairingCard = true
                    model.selectTab(.devices)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "iphone.gen3")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.green)
                            Spacer()
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                        Text("Android Phone")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("Scan QR code or enter 6-digit PIN")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)

                Button {
                    deviceTabMode = 0
                    showPairingCard = true
                    model.selectTab(.devices)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "laptopcomputer")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.blue)
                            Spacer()
                            Image(systemName: "chevron.right.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.secondary.opacity(0.6))
                        }
                        Text("Windows / PC")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("Connect via Relay PIN or LAN")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            Button {
                withAnimation {
                    model.cycleHistoryDeviceFilter()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                    Text("Return to All History")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.accent)
            }
            .buttonStyle(.link)
            .padding(.top, 4)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func deleteConfirmationDialogView(_ target: HistoryDeleteConfirmation) -> some View {
        ZStack {
            Color.black.opacity(0.45)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    deleteConfirmTarget = nil
                }

            VStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Color.red)

                Text(target.title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(.primary)

                Text(target.message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)

                HStack(spacing: 10) {
                    Button {
                        deleteConfirmTarget = nil
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        target.onConfirm()
                        deleteConfirmTarget = nil
                    } label: {
                        Text("Delete")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .frame(width: 280)
            .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .shadow(color: Color.black.opacity(0.25), radius: 16, x: 0, y: 8)
        }
        .transition(.opacity)
    }

    private func filterPill(_ filter: HistoryTypeFilter) -> some View {
        let isSelected = model.filter == filter
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.filter = filter
            }
        } label: {
            HStack(spacing: 4) {
                if filter == .pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9.5, weight: .bold))
                }
                Text(filter == .pinned ? "Pinned" : L10n.t(filter.labelKey))
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                isSelected ? AppColor.accent.opacity(0.18) : Color.primary.opacity(0.04),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? AppColor.accent.opacity(0.4) : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
            )
            .foregroundStyle(isSelected ? AppColor.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }
    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.loading { ProgressView().padding(30).frame(maxWidth: .infinity) }
                else if model.history.isEmpty { empty(.noHistory, hint: .panelNoHistoryHint, symbol: "clipboard") }
                else {
                    LazyVStack(spacing: 2) {
                        ForEach(model.history) { entry in historyRow(entry) }
                    }
                    .padding(.vertical, 2)
                }
            }
            .onHover { hovering in
                if !hovering && !model.isPreviewHovered {
                    model.schedulePreviewDismiss(delay: 0.15)
                }
            }
            .onChange(of: model.selectedID) { id in if let id { proxy.scrollTo(id) } }
        }
    }
    private func historyRow(_ entry: HistoryEntry) -> some View {
        MenuBarPanelHistoryRow(entry: entry,
                              selected: model.selectedID == "h:" + entry.id,
                              isSelectMode: model.isSelectMode,
                              isSelectedForDelete: model.selectedIDs.contains(entry.id),
                              onToggleSelect: { model.toggleSelectID(entry.id) },
                              onDelete: { promptDeleteEntry(entry) },
                              use: { model.onHistory?(entry, .use) },
                              copy: { model.onHistory?(entry, .copy) },
                              saveSnippet: { model.savingSnippetEntry = entry },
                              togglePin: { model.togglePin(entry) },
                              onDownload: { downloadImage(entry) })
            .id("h:" + entry.id)
            .onHover { isHovered in
                if isHovered {
                    model.hoverRow(entry)
                } else {
                    model.unhoverRow(entry)
                }
            }
            .contextMenu {
                Button(entry.isPinned ? "Unpin from Top" : "Pin to Top") { model.togglePin(entry) }
                Button(L10n.t(.panelUse)) { model.onHistory?(entry, .use) }
                Button(L10n.t(.copyContent)) { model.onHistory?(entry, .copy) }
                Button(L10n.t(.saveAsSnippet)) { model.savingSnippetEntry = entry }
                if case .image = entry.item {
                    Button("Download High-Res JPG") { downloadImage(entry) }
                }
                if entry.item.isFile {
                    Button(L10n.t(.pasteFileName)) { model.onHistory?(entry, .fileNames) }
                    Button(L10n.t(.showInFinder)) { model.onHistory?(entry, .reveal) }
                } else {
                    switch entry.item {
                    case .html, .rtf: Button(L10n.t(.pastePlainText)) { model.onHistory?(entry, .plainText) }
                    default: EmptyView()
                    }
                }
                Divider()
                Button(role: .destructive) {
                    promptDeleteEntry(entry)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    private func promptDeleteEntry(_ entry: HistoryEntry) {
        let displayTitle = entry.listDisplayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = displayTitle.count > 35 ? "\(displayTitle.prefix(35))..." : displayTitle
        deleteConfirmTarget = HistoryDeleteConfirmation(
            title: "Delete Item?",
            message: "Are you sure you want to delete '\(preview)'? This cannot be undone.",
            onConfirm: {
                model.deleteSingleEntry(entry)
                model.notice = "Deleted item"
            }
        )
    }
    private func downloadImage(_ entry: HistoryEntry) {
        guard case .image(let path) = entry.item else { return }
        exportHistoryImageAsJPG(path: path) { filename in
            if let filename {
                model.notice = "Saved to Downloads: \(filename)"
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    if model.notice?.contains(filename) == true {
                        model.notice = nil
                    }
                }
            } else {
                model.notice = "Failed to export JPG"
            }
        }
    }
    private var snippetsContent: some View {
        MenuBarPanelSnippetsTab(model: model)
    }
    private func snippetRow(_ snippet: Snippet) -> some View {
        Button { model.onSnippet?(snippet.id) } label: {
            HStack(spacing: 11) {
                Image(systemName: "folder").font(.system(size: 16)).foregroundStyle(AppColor.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snippet.title).lineLimit(1)
                    Text(snippet.content).font(AppFont.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 3)
                if let shortcut = snippet.shortcut { Text(shortcut.displayString).font(AppFont.caption).foregroundStyle(.secondary) }
            }.padding(11).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                .background(model.selectedID == "s:" + snippet.id.uuidString ? AppColor.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).id("s:" + snippet.id.uuidString)
            .onHover { if $0 { model.selectedID = "s:" + snippet.id.uuidString } }
    }
    private var searchResults: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if model.loading { ProgressView().padding().frame(maxWidth: .infinity) }
                        ForEach(model.history) { historyRow($0) }
                        ForEach(model.visibleSnippets) { snippetRow($0) }
                        toolList
                        if !model.loading && model.history.isEmpty && model.visibleSnippets.isEmpty && model.matchingTools.isEmpty {
                            empty(.panelEmptySearch, hint: .panelEmptyHint, symbol: "magnifyingglass")
                        }
                    }
                }.onChange(of: model.selectedID) { id in if let id { proxy.scrollTo(id) } }
            }
            actionLink(.panelAllHistory) { model.onAction?(.search(model.query)) }
        }
    }
    private var toolList: some View {
        VStack(spacing: 0) {
            ForEach(model.visibleTools, id: \.rawValue) { tool in
                toolRow(tool.title, detail: tool.hint, symbol: tool.symbol,
                        status: tool == .keepAwake ? L10n.t(keepAwake.isActive ? .keepAwakeOn : .keepAwakeOff) : nil,
                        active: tool == .keepAwake && keepAwake.isActive) { model.useTool(tool) }
                    .id("t:" + tool.rawValue)
                    .background(model.selectedID == "t:" + tool.rawValue ? AppColor.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                    .onHover { if $0 { model.selectedID = "t:" + tool.rawValue } }
            }
        }
    }
    private var devicesContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(L10n.t(.panelDevices)).font(AppFont.caption).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button(action: refreshDevices) {
                    HStack(spacing: 5) {
                        if refreshingDevices { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise") }
                        Text(L10n.t(refreshingDevices ? .refreshingDevices : .refreshDevices))
                    }.font(AppFont.secondary)
                }.buttonStyle(.bordered).controlSize(.small).disabled(refreshingDevices)
            }.padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 10) {
                    if !model.devices.isEmpty {
                        LazyVStack(spacing: 0) {
                            ForEach(model.devices, id: \.peerId) { device in
                                HStack(spacing: 10) {
                                    Image(systemName: "iphone.gen3")
                                        .font(.system(size: 21))
                                        .foregroundStyle(device.isOnline ? Color.green : Color.secondary)
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 6) {
                                            Text(device.displayName)
                                                .lineLimit(1)
                                                .font(.system(size: 13, weight: .semibold))
                                            Circle()
                                                .fill(device.isOnline ? Color.green : Color.gray.opacity(0.8))
                                                .frame(width: 6, height: 6)
                                            Text(device.isOnline ? "Online" : "Disconnected")
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(device.isOnline ? Color.green : Color.secondary)
                                        }
                                        Text(device.connectionDescription)
                                            .font(AppFont.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .help(device.connectionDescription)
                                    }
                                    Spacer()
                                    if device.isOnline {
                                        Button(L10n.t(.panelSendText)) { model.onAction?(.sendText(device.peerId)) }
                                            .buttonStyle(.bordered).controlSize(.small).fixedSize()
                                        Button(L10n.t(.panelSendFile)) { model.onAction?(.sendFile(device.peerId)) }
                                            .buttonStyle(.bordered).controlSize(.small).fixedSize()
                                    } else {
                                        Button {
                                            SyncManager.shared.reconnectDevice(peerId: device.peerId)
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: "bolt.fill")
                                                Text("Connect")
                                            }
                                            .font(.system(size: 11, weight: .semibold))
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .controlSize(.small)
                                        .fixedSize()

                                        Button {
                                            SyncManager.shared.removeSavedDevice(peerId: device.peerId)
                                            model.devices = SyncManager.shared.availableDeviceEntries
                                        } label: {
                                            Image(systemName: "trash")
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Forget Device")
                                    }
                                }.padding(.vertical, 8)
                                Divider()
                            }
                        }

                        Button {
                            showPairingCard.toggle()
                        } label: {
                            Label(showPairingCard ? "পেয়ারিং QR কোড লুকান" : "অন্য ডিভাইস যুক্ত করুন (Pair Another Device)", systemImage: "qrcode")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.link)
                        .padding(.top, 2)
                    }

                    if model.devices.isEmpty || showPairingCard {
                        devicePairingAndDownloadCard
                    }

                    actionLink(.panelSyncSettings) { model.onAction?(.syncSettings) }
                }
            }
        }
        .onAppear {
            relayGroups.ensureReady()
        }
    }

    private var devicePairingAndDownloadCard: some View {
        VStack(spacing: 10) {
            Picker("", selection: $deviceTabMode) {
                Text("📱 Pair Android Phone").tag(0)
                Text("⬇️ Download APK").tag(1)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 4)

            if deviceTabMode == 0 {
                // Pair Device Tab (For Android app "Scan Mac QR Code" & 6-digit PIN)
                VStack(spacing: 8) {
                    let ips = SyncManager.localIPv4Addresses()
                    let primaryIP = ips.first ?? "127.0.0.1"
                    let macPin = relayGroups.shortPin.replacingOccurrences(of: " ", with: "")
                    let payloadDict: [String: Any] = [
                        "app": "techuboard",
                        "v": 1,
                        "id": SyncManager.shared.peerId,
                        "name": Host.current().localizedName ?? SyncManager.shared.displayName,
                        "pk": SyncCryptoV4.shared.staticPublicKeyHex,
                        "ips": ips,
                        "ip": primaryIP,
                        "port": Int(SyncManager.shared.syncPort),
                        "pin": macPin,
                        "relay": relayGroups.pairingCode ?? ""
                    ]
                    let pairingCode = (try? JSONSerialization.data(withJSONObject: payloadDict))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{\"app\":\"techuboard\",\"v\":1,\"id\":\"\(SyncManager.shared.peerId)\",\"name\":\"Mac\",\"ip\":\"\(primaryIP)\",\"port\":5566,\"pin\":\"\(macPin)\"}"

                    if let qr = qrImage(for: pairingCode) {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 130, height: 130)
                            .padding(6)
                            .background(Color.white)
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    }

                    Text("Android অ্যাপে 'Scan Mac QR Code' বাটনে ট্যাপ করে স্ক্যান করুন")
                        .font(.system(size: 11, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)

                    Divider().padding(.horizontal, 16)

                    VStack(spacing: 4) {
                        Text("অথবা ফোনে এই ৬-ডিজিটের কোড দিন:")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Text(relayGroups.shortPin)
                                .font(.system(size: 20, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.accentColor)
                                .textSelection(.enabled)

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(macPin, forType: .string)
                                copiedPairingPin = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedPairingPin = false
                                }
                            } label: {
                                Image(systemName: copiedPairingPin ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 11))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("পিন কপি করুন")
                        }

                        if primaryIP != "127.0.0.1" {
                            Text("Wi-Fi IP: \(primaryIP):\(SyncManager.shared.syncPort)")
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.8))
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(.vertical, 8)
            } else {
                // Download APK Tab
                VStack(spacing: 8) {
                    if let qr = qrImage(for: "https://github.com/Anzaar-riajul/Anzaar-engine-1.0/releases/latest/download/Techuboard-Android-v1.0.apk") {
                        Image(nsImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .padding(6)
                            .background(Color.white)
                            .cornerRadius(8)
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

                        Text("ফোনের ক্যামেরা দিয়ে স্ক্যান করুন")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("স্ক্যান করলেই সরাসরি সর্বশেষ APK ডাউনলোড শুরু হবে")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        Button {
                            if let url = Bundle.main.url(forResource: "Techuboard-Android", withExtension: "apk") {
                                let picker = NSSharingServicePicker(items: [url])
                                if let window = NSApp.keyWindow {
                                    picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
                                }
                            } else if let landingPage = URL(string: "https://anzaar-riajul.github.io/Anzaar-engine-1.0/") {
                                NSWorkspace.shared.open(landingPage)
                            }
                        } label: {
                            Label("AirDrop / Share APK", systemImage: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            if let landingPage = URL(string: "https://anzaar-riajul.github.io/Anzaar-engine-1.0/") {
                                NSWorkspace.shared.open(landingPage)
                            }
                        } label: {
                            Label("ডাউনলোড পেজ", systemImage: "globe")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
    /// Same user refresh as the menu and settings: prune ghosts + full /24 scan.
    private func refreshDevices() {
        guard !refreshingDevices else { return }
        refreshingDevices = true
        SyncManager.shared.refreshDiscovery(pruneCache: true, scanFullSubnet: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { refreshingDevices = false }
    }
    private func qrImage(for text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let outputImage = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 5, y: 5)
        let scaled = outputImage.transformed(by: transform)
        let rep = NSCIImageRep(ciImage: scaled)
        let nsImage = NSImage(size: rep.size)
        nsImage.addRepresentation(rep)
        return nsImage
    }
    private var notificationsContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                if model.notifications.isEmpty { empty(.noNotifications, hint: nil, symbol: "bell") }
                else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.notifications) { notification in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(notification.appName).font(AppFont.caption).foregroundStyle(.secondary)
                                Text(notification.title).font(.system(size: 13, weight: .medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(notification.body).font(AppFont.secondary).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }
                }
            }
            actionLink(.panelAllNotifications) { model.onAction?(.notifications) }
        }
    }
    private var settingsContent: some View {
        ScrollView {
            VStack(spacing: 12) {
                settingsGeneralSection
                settingsTechuAvroSection
                settingsDevicesSection
                settingsShortcutsSection
                settingsActionsSection
            }
            .padding(.vertical, 8)
        }
        .confirmationDialog("Clear Unpinned History?", isPresented: $showClearHistoryConfirm, titleVisibility: .visible) {
            Button("Clear Unpinned Items", role: .destructive) {
                ClipboardManager.shared.clearHistory()
                model.refreshHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Pinned clips and notes will be kept safely. Only unpinned clipboard history will be cleared.")
        }
    }

    private var settingsGeneralSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 26, height: 26)
                    .background(AppColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Start Techuboard automatically when your Mac starts")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: launchAtLogin) { enabled in
                        try? LaunchAtLoginManager.setEnabled(enabled)
                    }
            }
            .padding(10)

            Divider().padding(.horizontal, 10)

            HStack(spacing: 12) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 26, height: 26)
                    .background(AppColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep Panel Open")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Stay open when clicking outside")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $model.pinned)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .padding(10)

            Divider().padding(.horizontal, 10)

            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 26, height: 26)
                    .background(AppColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("History Capacity")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Maximum clipboard items to keep")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("100 items") {
                        clipboardHistoryLimit = 100
                        PreferencesManager.shared.historyLimit = 100
                    }
                    Button("250 items") {
                        clipboardHistoryLimit = 250
                        PreferencesManager.shared.historyLimit = 250
                    }
                    Button("500 items") {
                        clipboardHistoryLimit = 500
                        PreferencesManager.shared.historyLimit = 500
                    }
                    Button("1,000 items") {
                        clipboardHistoryLimit = 1000
                        PreferencesManager.shared.historyLimit = 1000
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(clipboardHistoryLimit == 1000 ? "1,000 items" : "\(clipboardHistoryLimit) items")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(10)

            Divider().padding(.horizontal, 10)

            HStack(spacing: 12) {
                Image(systemName: "photo.stack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.orange)
                    .frame(width: 26, height: 26)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Delete Old Images")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text(imageAutoDelete ? "Retains newest \(imageDeleteLimit) screenshots" : "Keep all screenshots")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $imageAutoDelete)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: imageAutoDelete) { enabled in
                        PreferencesManager.shared.isImageAutoDeleteEnabled = enabled
                        if enabled { ClipboardManager.shared.applyImageAutoDeleteLimit() }
                    }
            }
            .padding(10)

            if imageAutoDelete {
                Divider().padding(.horizontal, 10)
                HStack {
                    Text("Screenshot limit:")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: $imageDeleteLimit) {
                        Text("10").tag(10)
                        Text("20").tag(20)
                        Text("30").tag(30)
                        Text("40").tag(40)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .onChange(of: imageDeleteLimit) { limit in
                        PreferencesManager.shared.imageAutoDeleteThreshold = limit
                        ClipboardManager.shared.applyImageAutoDeleteLimit()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var settingsTechuAvroSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with authentic logo, title, and status pill
            HStack(spacing: 10) {
                // Creative glowing icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.28), Color.purple.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.8)
                        )

                    if let iconURL = Bundle.main.url(forResource: "MenuBarIcon@2x", withExtension: "png") ?? Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
                       let nsImg = NSImage(contentsOf: iconURL) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 14)
                            .foregroundStyle(Color.cyan)
                    } else {
                        Image(systemName: "keyboard.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.cyan)
                    }
                }
                .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("TechuAvro Bangla Keyboard")
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(Color.primary)
                        Text("NATIVE")
                            .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing),
                                in: Capsule()
                            )
                    }
                    Text("Phonetic Avro Input Method for macOS")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()

                // Status pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(isAvroInstalled ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(isAvroInstalled ? "Active" : "Not Installed")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isAvroInstalled ? Color.green : Color.orange)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    isAvroInstalled ? Color.green.opacity(0.12) : Color.orange.opacity(0.12),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(isAvroInstalled ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), lineWidth: 0.5)
                )
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Creative Phonetic Demonstration Pill (Instant user clarity)
            HStack(spacing: 8) {
                Text("Phonetic:")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text("ami")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("আমি")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.cyan)
                }
                Text("·")
                    .foregroundStyle(.tertiary)
                HStack(spacing: 4) {
                    Text("bangla")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("বাংলা")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.cyan)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .padding(.horizontal, 12)

            // Action Buttons
            HStack(spacing: 8) {
                if isAvroWorking {
                    ProgressView().scaleEffect(0.7)
                    Text("Configuring System Input Method...").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Button {
                        isAvroWorking = true
                        let bundleURL = TechuAvroInstaller.findBundleURL()
                        TechuAvroInstaller.install(from: bundleURL) { err in
                            isAvroWorking = false
                            isAvroInstalled = TechuAvroInstaller.isInstalled()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isAvroInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(isAvroInstalled ? "Reinstall / Verify" : "1-Click Install TechuAvro")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.85), Color.cyan.opacity(0.85)],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.blue.opacity(0.25), radius: 4, y: 1.5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape")
                                .font(.system(size: 10, weight: .medium))
                            Text("Keyboard Settings")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.08),
                    Color.purple.opacity(0.05),
                    Color.cyan.opacity(0.03)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.blue.opacity(0.35),
                            Color.cyan.opacity(0.2),
                            Color.purple.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.8
                )
        )
    }

    private var settingsDevicesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .frame(width: 26, height: 26)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Device Sync")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Sync clips between Mac, Android, and PC")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $syncEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: syncEnabled) { enabled in
                        PreferencesManager.shared.isSyncEnabled = enabled
                    }
            }
            .padding(10)

            Divider().padding(.horizontal, 10)

            HStack(spacing: 12) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.purple)
                    .frame(width: 26, height: 26)
                    .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-Sync Photos & Files")
                        .font(.system(size: 12.5, weight: .semibold))
                    Text("Instantly transfer images copied on either device")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $autoImageSync)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: autoImageSync) { enabled in
                        PreferencesManager.shared.isAutoImageSyncEnabled = enabled
                    }
            }
            .padding(10)

            if !model.devices.isEmpty {
                Divider().padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected Devices (\(model.devices.count))")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 6)
                    ForEach(model.devices, id: \.peerId) { dev in
                        deviceRow(dev: dev)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func deviceRow(dev: DeviceEntry) -> some View {
        HStack(spacing: 8) {
            Circle().fill(dev.isOnline ? Color.green : Color.gray).frame(width: 7, height: 7)
            Text(dev.displayName)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(dev.connectionDescription)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            if !dev.isOnline {
                Button {
                    SyncManager.shared.reconnectDevice(peerId: dev.peerId)
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("Reconnect")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var settingsShortcutsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "command")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.accent)
                    .frame(width: 26, height: 26)
                    .background(AppColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                Text("Shortcuts Guide")
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
            }
            .padding(10)

            Divider().padding(.horizontal, 10)

            VStack(spacing: 6) {
                shortcutItem(title: "Open Clipboard History", keys: "Command + Shift + V")
                shortcutItem(title: "Search Clips", keys: "Command + F")
                shortcutItem(title: "Paste Selected Clip", keys: "Return (Enter)")
                shortcutItem(title: "Quick Side Preview", keys: "Hover Mouse")
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private var settingsActionsSection: some View {
        VStack(spacing: 0) {
            Button {
                model.onAction?(.permission)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22)
                    Text("Accessibility Permission")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, 10)

            Button {
                showClearHistoryConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.red)
                        .frame(width: 22)
                    Text("Clear Unpinned History")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.red)
                    Spacer()
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().padding(.horizontal, 10)

            Button {
                model.onAction?(.quit)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 22)
                    Text("Quit Techuboard")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                    Spacer()
                }
                .padding(10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }

    private func shortcutItem(title: String, keys: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
            Spacer()
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
        }
    }
    private var footer: some View {
        ViewThatFits(in: .horizontal) {
            footerRow(showLabels: true)
            footerRow(showLabels: false)
        }
    }
    private func footerRow(showLabels: Bool) -> some View {
        HStack(spacing: 6) {
            quick(.panelLookupShortcut, symbol: "character.book.closed", showLabel: showLabels) { model.onAction?(.word) }
            quick(.panelSwitchShortcut, symbol: "arrow.triangle.swap", showLabel: showLabels) { model.onAction?(.smartSwitch) }
            Spacer(minLength: 4)
            popupToggle
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 16)
            Button { model.navigate(.tools) } label: {
                Text(L10n.t(.menuTools))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }.buttonStyle(.plain)
            Button { model.navigate(.notifications) } label: {
                Image(systemName: "bell")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
                    .overlay(alignment: .topTrailing) {
                        if model.notificationCount > 0 {
                            Text(model.notificationCount > 99 ? "99+" : "\(model.notificationCount)")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(Color.red, in: Capsule())
                                .offset(x: 3, y: -3)
                        }
                    }
            }.buttonStyle(.plain).help(L10n.t(.notificationSync)).accessibilityLabel(L10n.t(.notificationSync))
            Menu {
                Button(L10n.t(.preferences)) { model.onAction?(.preferences) }
                Button(L10n.t(.overflowRefresh)) { overflow.refreshForMenu() }
                Divider()
                Button(L10n.t(.quit)) { model.onAction?(.quit) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help(L10n.t(.panelMore)).accessibilityLabel(L10n.t(.panelMore))
        }
    }
    private var popupToggle: some View {
        HStack(spacing: 4) {
            Image(systemName: notificationPopups.enabled ? "bell.fill" : "bell.slash")
                .font(.system(size: 11))
                .foregroundStyle(notificationPopups.enabled ? AppColor.accent : Color.secondary)
                .frame(width: 14)
            Toggle(isOn: Binding(get: { notificationPopups.enabled }, set: { notificationPopups.setEnabled($0) })) {
                Text(L10n.t(.notificationPopups))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .labelsHidden()
        }
        .fixedSize()
        .help(L10n.t(.notificationPopups) + "\n" + L10n.t(.notificationPopupsHint))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.t(.notificationPopups))
    }
    private func quick(_ key: L10nKey, symbol: String, showLabel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if showLabel { Label(L10n.t(key), systemImage: symbol).fixedSize() }
                else { Image(systemName: symbol) }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, showLabel ? 7 : 6)
            .frame(height: 26)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .foregroundStyle(Color.secondary)
        }.buttonStyle(.plain).help(L10n.t(key)).accessibilityLabel(L10n.t(key))
    }
    private func iconButton(_ key: L10nKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
                .foregroundStyle(Color.secondary)
        }.buttonStyle(.plain).help(L10n.t(key)).accessibilityLabel(L10n.t(key))
    }
    private func pill(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .background(
                    selected ? AppColor.accent.opacity(0.12) : Color.primary.opacity(0.035),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        selected ? AppColor.accent.opacity(0.2) : Color.primary.opacity(0.04),
                        lineWidth: 0.5
                    )
                )
                .foregroundStyle(selected ? AppColor.accent : Color.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private func toolRow(_ title: L10nKey, detail: L10nKey?, symbol: String,
                         status: String? = nil, active: Bool = false,
                         action: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: symbol).font(.system(size: 16)).frame(width: 22).foregroundStyle(AppColor.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t(title)).font(.system(size: 12.5, weight: .medium))
                        if let detail { Text(L10n.t(detail)).font(AppFont.caption).foregroundStyle(.secondary).lineLimit(2) }
                    }
                    Spacer()
                    if let status {
                        Text(status).font(AppFont.caption)
                            .foregroundStyle(active ? AppColor.accent : Color.secondary)
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }.padding(.horizontal, 8).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(status ?? "")
            Rectangle().fill(Color.primary.opacity(0.04)).frame(height: 0.5)
        }
    }
    private func actionLink(_ key: L10nKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(L10n.t(key))
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 11, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColor.accent)
    }
    private func empty(_ title: L10nKey, hint: L10nKey?, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 28, weight: .ultraLight)).foregroundStyle(.tertiary)
            Text(L10n.t(title)).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            if let hint { Text(L10n.t(hint)).font(.system(size: 11)).foregroundStyle(.tertiary).multilineTextAlignment(.center) }
            if title == .noHistory {
                VStack(spacing: 6) {
                    Text("Quick Sample Clips (Click to Copy):")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                    HStack(spacing: 6) {
                        sampleChip("TechuAvro", text: "আমি বাংলায় গান গাই", color: .green)
                        sampleChip("URL", text: "https://github.com/techuboard/app", color: .purple)
                        sampleChip("Code", text: "TECHUBOARD_KEY", color: .orange)
                    }
                }
            }
        }.padding(title == .noHistory ? 16 : 22).frame(maxWidth: .infinity, minHeight: 125)
    }

    private func sampleChip(_ label: String, text: String, color: Color) -> some View {
        Button {
            ClipboardManager.shared.copyToPasteboard(.text(text), simulatePaste: false)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 3))
                Text(text)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Click to copy sample to clipboard")
    }
}

private struct MenuBarPanelHistoryRow: View {
    let entry: HistoryEntry
    let selected: Bool
    var isSelectMode: Bool = false
    var isSelectedForDelete: Bool = false
    var onToggleSelect: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let use: () -> Void
    let copy: () -> Void
    let saveSnippet: () -> Void
    let togglePin: () -> Void
    var onDownload: (() -> Void)? = nil
    @StateObject private var thumbnail = MenuBarPanelThumbnail()
    private var symbol: String {
        switch entry.item {
        case .image: return "photo"
        case .files: return "doc"
        case .html: return "chevron.left.forwardslash.chevron.right"
        case .rtf: return "doc.richtext"
        case .pdf: return "doc.text"
        case .text: return entry.isPinned ? "pin" : "text.alignleft"
        }
    }
    private var isPlainText: Bool {
        switch entry.item {
        case .text: return !entry.isPinned
        default: return false
        }
    }
    private var fullText: String {
        entry.resolvedText ?? ClipboardManager.shared.plainText(for: entry.item) ?? entry.item.fileURLs?.map(\.path).joined(separator: "\n") ?? entry.listDisplayTitle
    }
    private var badgeInfo: (label: String, color: Color)? {
        let title = entry.listDisplayTitle
        for scalar in title.unicodeScalars {
            if scalar.value >= 0x0980 && scalar.value <= 0x09FF {
                return ("TechuAvro", Color.green)
            }
        }
        if title.hasPrefix("http://") || title.hasPrefix("https://") {
            return ("URL", Color.purple)
        }
        if title.contains("=") || title.contains("function ") || title.contains("var ") || title.contains("let ") || title.contains("const ") || title.contains("{") {
            return ("Code", Color.orange)
        }
        return nil
    }
    var body: some View {
        HStack(spacing: 6) {
            if isSelectMode {
                Button {
                    onToggleSelect?()
                } label: {
                    Image(systemName: isSelectedForDelete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: isSelectedForDelete ? .bold : .regular))
                        .foregroundStyle(isSelectedForDelete ? AppColor.accent : Color.secondary.opacity(0.55))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }

            if case .image = entry.item {
                ZStack(alignment: .bottomTrailing) {
                    Button(action: {
                        if isSelectMode {
                            onToggleSelect?()
                        } else {
                            use()
                        }
                    }) {
                        if let image = thumbnail.image {
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 38, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 13, weight: .light))
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 26, height: 26)
                        }
                    }
                    .buttonStyle(.plain)

                    if let onDownload {
                        Button(action: onDownload) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.white)
                                .background(Color.black.opacity(0.7), in: Circle())
                                .shadow(color: Color.black.opacity(0.35), radius: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(2)
                        .help("Download high-res JPG")
                    }
                }
                .frame(width: 38, height: 26)
            } else if !isPlainText {
                Button(action: {
                    if isSelectMode {
                        onToggleSelect?()
                    } else {
                        use()
                    }
                }) {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(AppColor.accent)
                        .frame(width: 20)
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                if isSelectMode {
                    onToggleSelect?()
                } else {
                    use()
                }
            }) {
                HStack(spacing: 5) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(AppColor.accent)
                    }
                    if let badge = badgeInfo {
                        Text(badge.label)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(badge.color)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(badge.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 3.5))
                    }
                    Text(entry.listDisplayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selected {
                HStack(spacing: 3) {
                    Button(action: togglePin) {
                        Image(systemName: entry.isPinned ? "pin.slash.fill" : "pin.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(entry.isPinned ? AppColor.accent : Color.primary.opacity(0.8))
                            .frame(width: 22, height: 22)
                            .background(entry.isPinned ? AppColor.accent.opacity(0.15) : Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help(entry.isPinned ? "Unpin from Top" : "Pin to Top")

                    Button(action: saveSnippet) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.8))
                            .frame(width: 22, height: 22)
                            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Save as Note")

                    Button(action: { onDelete?() }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.red.opacity(0.85))
                            .frame(width: 22, height: 22)
                            .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Delete Item")
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    if entry.isPinned {
                        Button(action: togglePin) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColor.accent)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("Unpin from Top")
                    } else if let source = entry.sourceApp {
                        Text(source)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.75))
                            .lineLimit(1)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 3.5))
                    }
                    Text(RelativeTimeFormatter.string(from: entry.date))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 85, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 34)
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
        .background(
            selected ? AppColor.accent.opacity(0.12) : Color.clear,
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(selected ? AppColor.accent.opacity(0.2) : Color.clear, lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(AppColor.accent)
                    .frame(width: 3, height: 16)
                    .padding(.leading, 2)
            }
        }
        .onAppear {
            if case .image(let path) = entry.item { thumbnail.load(path) }
        }
        .onDisappear { thumbnail.cancel() }
    }
}

private final class MenuBarPanelThumbnail: ObservableObject {
    @Published var image: NSImage?
    private var revision = 0
    func load(_ path: String) {
        revision += 1
        let ticket = revision
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let image = HistoryThumbnailCache.thumbnail(for: path, size: NSSize(width: 92, height: 68))
            DispatchQueue.main.async { [weak self] in
                guard let self, self.revision == ticket else { return }
                self.image = image
            }
        }
    }
    func cancel() { revision += 1; image = nil }
}

/// AppKit field delegates navigation only after the input method has finished composition.
private struct MenuBarPanelSearchField: NSViewRepresentable {
    @ObservedObject var model: MenuBarPanelModel
    func makeCoordinator() -> Coordinator { Coordinator(model) }
    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.delegate = context.coordinator
        field.isBordered = false; field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.cell?.usesSingleLineMode = true
        (field.cell as? NSSearchFieldCell)?.searchButtonCell = nil
        (field.cell as? NSSearchFieldCell)?.cancelButtonCell = nil
        field.setAccessibilityLabel(L10n.t(.panelSearch))
        return field
    }
    func updateNSView(_ field: NSSearchField, context: Context) {
        field.placeholderAttributedString = NSAttributedString(string: L10n.t(.panelSearch), attributes: AppFont.textAttributes(size: 14, color: .secondaryLabelColor))
        field.setAccessibilityLabel(L10n.t(.panelSearch))
        let composing = (field.currentEditor() as? NSTextView)?.hasMarkedText() == true
        if !composing && field.stringValue != model.query { field.stringValue = model.query }
        if context.coordinator.focusRequest != model.focusRequest {
            context.coordinator.focusRequest = model.focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, field.window?.isVisible == true else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        let model: MenuBarPanelModel
        var focusRequest = 0
        init(_ model: MenuBarPanelModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField,
                  (field.currentEditor() as? NSTextView)?.hasMarkedText() != true else { return }
            if model.page != .home { model.page = .home }
            model.query = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            switch commandSelector {
            case #selector(NSResponder.moveDown(_:)): model.moveSelection(1); return true
            case #selector(NSResponder.moveUp(_:)): model.moveSelection(-1); return true
            case #selector(NSResponder.insertNewline(_:)): model.useSelection(); return true
            default: return false
            }
        }
    }
}

private struct MenuBarPanelSaveSnippetView: View {
    let entry: HistoryEntry
    @ObservedObject var model: MenuBarPanelModel
    @State private var selectedFolderId: UUID?
    @State private var headline: String = ""
    @State private var showCreateFolder = false
    @State private var newFolderName: String = ""
    @FocusState private var isHeadlineFocused: Bool

    private var contentToSave: String {
        switch entry.item {
        case .text: return entry.resolvedText ?? entry.item.title
        case .files(let urls): return urls.map(\.lastPathComponent).joined(separator: "\n")
        default: return ClipboardManager.shared.plainText(for: entry.item) ?? entry.item.title
        }
    }

    private var currentFolders: [SnippetFolder] {
        SnippetManager.shared.folders
    }

    private var selectedFolder: SnippetFolder? {
        guard let id = selectedFolderId else { return nil }
        return currentFolders.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    if selectedFolderId != nil {
                        selectedFolderId = nil
                    } else {
                        model.savingSnippetEntry = nil
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text(selectedFolderId != nil ? L10n.t(.snippetFolders) : L10n.t(.panelBack))
                    }
                    .font(AppFont.secondary)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accent)

                Spacer()

                Text(selectedFolder?.title ?? L10n.t(.addSnippet))
                    .font(AppFont.section)
                    .lineLimit(1)

                Spacer()

                Button {
                    model.savingSnippetEntry = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 10)

            Divider().padding(.bottom, 8)

            if let folder = selectedFolder {
                // Folder is selected: Headline input at the top + List of snippets below
                VStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.t(.snippetTitle))
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            TextField(L10n.t(.snippetTitle), text: $headline)
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))
                                .focused($isHeadlineFocused)
                                .onSubmit { save(to: folder) }

                            Button(L10n.t(.save)) {
                                save(to: folder)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(headline.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))

                    // Snippet preview card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.t(.snippetFallback))
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(contentToSave.count) chars")
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(contentToSave)
                            .font(AppFont.secondary)
                            .lineLimit(3)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.horizontal, 2)

                    // Existing snippets in this folder
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(folder.title)
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(folder.snippets.count)")
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)

                        ScrollView {
                            if folder.snippets.isEmpty {
                                Text(L10n.t(.noSnippets))
                                    .font(AppFont.secondary)
                                    .foregroundStyle(.secondary)
                                    .padding(20)
                                    .frame(maxWidth: .infinity)
                            } else {
                                LazyVStack(spacing: 6) {
                                    ForEach(folder.snippets) { s in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(s.title)
                                                .font(AppFont.body.weight(.medium))
                                                .lineLimit(1)
                                            Text(s.content)
                                                .font(AppFont.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }

                    Spacer(minLength: 0)
                }
                .onAppear {
                    if headline.isEmpty {
                        headline = String(entry.listDisplayTitle.prefix(50))
                    }
                    isHeadlineFocused = true
                }
            } else {
                // Folder Selection List
                VStack(spacing: 8) {
                    HStack {
                        Text(L10n.t(.snippetFolders))
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            showCreateFolder.toggle()
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "folder.badge.plus")
                                Text(L10n.t(.addFolder))
                            }
                            .font(AppFont.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColor.accent)
                    }

                    if showCreateFolder {
                        HStack(spacing: 6) {
                            TextField(L10n.t(.folderName), text: $newFolderName)
                                .textFieldStyle(.plain)
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))

                            Button(L10n.t(.save)) {
                                let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    SnippetManager.shared.addFolder(title: trimmed)
                                    model.folders = SnippetManager.shared.folders
                                    newFolderName = ""
                                    showCreateFolder = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .padding(6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(currentFolders) { folder in
                                Button {
                                    selectedFolderId = folder.id
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(AppColor.accent)
                                            .font(.system(size: 16))
                                        Text(folder.title)
                                            .font(AppFont.body)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(folder.snippets.count)")
                                            .font(AppFont.caption)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.primary.opacity(0.06), in: Capsule())
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(6)
    }

    private func save(to folder: SnippetFolder) {
        let title = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = title.isEmpty ? String(contentToSave.prefix(30)) : title
        SnippetManager.shared.addSnippet(to: folder.id, title: finalTitle, content: contentToSave)
        model.folders = SnippetManager.shared.folders
        model.notice = "\(finalTitle) → \(folder.title)"
        model.savingSnippetEntry = nil
    }
}

private struct MenuBarPanelSnippetsTab: View {
    @ObservedObject var model: MenuBarPanelModel
    @State private var expandedFolderIDs: Set<UUID> = []
    @State private var selectedDeviceFilter: String = "all"
    
    // Add Folder
    @State private var isAddingFolder = false
    @State private var newFolderName = ""
    
    // Edit Folder
    @State private var editingFolderId: UUID?
    @State private var editFolderTitle = ""
    
    // Add Snippet to folder
    @State private var addingSnippetFolderId: UUID?
    @State private var newSnippetTitle = ""
    @State private var newSnippetContent = ""
    
    // Edit Snippet
    @State private var editingSnippetId: UUID?
    @State private var editSnippetTitle = ""
    @State private var editSnippetContent = ""
    
    // Delete Confirmation Target
    struct DeleteTarget: Identifiable {
        let id = UUID()
        let isFolder: Bool
        let folderId: UUID
        let snippetId: UUID?
        let name: String
    }
    @State private var deleteTarget: DeleteTarget?

    // Clipboard History Picker Target
    enum ClipboardPickerTarget {
        case newSnippet
        case editSnippet
    }
    @State private var clipboardPickerTarget: ClipboardPickerTarget?

    private var availableDevices: [String] {
        var list: [String] = []
        for d in model.devices {
            if !list.contains(d.displayName) && d.displayName.lowercased() != "mac" {
                list.append(d.displayName)
            }
        }
        for f in model.folders {
            if let dev = f.deviceName, dev.lowercased() != "mac", !list.contains(dev) {
                list.append(dev)
            }
            for s in f.snippets {
                if let dev = s.deviceName, dev.lowercased() != "mac", !list.contains(dev) {
                    list.append(dev)
                }
            }
        }
        return list
    }

    private var allDeviceTabs: [(id: String, label: String, icon: String)] {
        var tabs: [(id: String, label: String, icon: String)] = [
            ("all", "All Notes", "square.grid.2x2"),
            ("mac", "This Mac", "laptopcomputer")
        ]
        var addedRemotes = Set<String>()
        for dev in availableDevices {
            tabs.append((dev.lowercased(), dev, "phone"))
            addedRemotes.insert(dev.lowercased())
        }
        if !addedRemotes.contains("android") {
            tabs.append(("android", "Android", "phone"))
        }
        return tabs
    }

    private func snippetsForFolder(_ folder: SnippetFolder) -> [Snippet] {
        if selectedDeviceFilter == "all" {
            return folder.snippets
        }
        if selectedDeviceFilter == "mac" {
            return folder.snippets.filter { ($0.deviceName?.lowercased() ?? "mac") == "mac" }
        }
        return folder.snippets.filter { ($0.deviceName?.lowercased() ?? "").contains(selectedDeviceFilter) }
    }

    private var displayedFolders: [SnippetFolder] {
        if selectedDeviceFilter == "all" {
            return model.folders
        }
        return model.folders.filter { folder in
            !snippetsForFolder(folder).isEmpty || (folder.deviceName?.lowercased() ?? "mac").contains(selectedDeviceFilter)
        }
    }

    private func deviceFilterPill(id: String, label: String, icon: String) -> some View {
        let isSelected = selectedDeviceFilter == id
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDeviceFilter = id
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9.5, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                isSelected ? AppColor.accent.opacity(0.18) : Color.primary.opacity(0.04),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? AppColor.accent.opacity(0.4) : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
            )
            .foregroundStyle(isSelected ? AppColor.accent : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(spacing: 6) {
            // Header bar
            HStack {
                Text(L10n.t(.snippets))
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAddingFolder.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text(L10n.t(.addFolder))
                    }
                    .font(AppFont.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accent)
            }
            .padding(.horizontal, 4)

            // Device Filter Tabs (All Notes, This Mac, Android, etc.)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(allDeviceTabs, id: \.id) { tab in
                        deviceFilterPill(id: tab.id, label: tab.label, icon: tab.icon)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 2)
            }

            // New folder input form
            if isAddingFolder {
                HStack(spacing: 6) {
                    TextField(L10n.t(.folderName), text: $newFolderName)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12)))

                    Button(L10n.t(.save)) {
                        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            SnippetManager.shared.addFolder(title: trimmed)
                            model.folders = SnippetManager.shared.folders
                            newFolderName = ""
                            isAddingFolder = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(L10n.t(.panelBack)) {
                        isAddingFolder = false
                        newFolderName = ""
                    }
                    .buttonStyle(.plain)
                    .font(AppFont.caption)
                }
                .padding(6)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }

            // Folders list with expandable accordion
            ScrollView {
                if displayedFolders.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text(selectedDeviceFilter == "all" ? L10n.t(.noSnippets) : "No notes for \(selectedDeviceFilter.capitalized)")
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                    }
                    .padding(30)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(displayedFolders) { folder in
                            folderSection(folder)
                        }
                    }
                }
            }
            .onHover { hovering in
                if !hovering && !model.isPreviewHovered {
                    model.schedulePreviewDismiss(delay: 0.15)
                }
            }

            actionLink(.panelManageSnippets) { model.onAction?(.snippets) }
        }
        .onAppear {
            if expandedFolderIDs.isEmpty, let first = model.folders.first {
                expandedFolderIDs.insert(first.id)
            }
        }
        .overlay {
            if let target = deleteTarget {
                ZStack {
                    Color.black.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                        .onTapGesture {
                            deleteTarget = nil
                        }
                    
                    VStack(spacing: 12) {
                        Image(systemName: "trash.circle.fill")
                            .font(.system(size: 34))
                            .foregroundStyle(Color.red)
                        
                        Text(target.isFolder ? "Delete Folder?" : "Delete Snippet?")
                            .font(AppFont.title)
                            .foregroundStyle(.primary)
                        
                        Text(target.isFolder ? "Are you sure you want to delete folder '\(target.name)' and all its snippets? This cannot be undone." : "Are you sure you want to delete snippet '\(target.name)'?")
                            .font(AppFont.secondary)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                        
                        HStack(spacing: 10) {
                            Button {
                                deleteTarget = nil
                            } label: {
                                Text("Cancel")
                                    .font(AppFont.body)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            
                            Button {
                                if target.isFolder {
                                    SnippetManager.shared.deleteFolder(id: target.folderId)
                                    expandedFolderIDs.remove(target.folderId)
                                } else if let sId = target.snippetId {
                                    SnippetManager.shared.deleteSnippet(id: sId)
                                }
                                model.folders = SnippetManager.shared.folders
                                model.notice = "Deleted: \(target.name)"
                                deleteTarget = nil
                            } label: {
                                Text("Delete")
                                    .font(AppFont.body.weight(.semibold))
                                    .foregroundStyle(Color.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .background(Color.red, in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .padding(16)
                    .frame(maxWidth: 300)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
                    .shadow(color: Color.black.opacity(0.35), radius: 16, x: 0, y: 6)
                }
            }
            if let pickerTarget = clipboardPickerTarget {
                SnippetClipboardPickerSheet(
                    onSelect: { entry in
                        let text = entry.resolvedText ?? ClipboardManager.shared.plainText(for: entry.item) ?? entry.item.fileURLs?.map(\.path).joined(separator: "\n") ?? entry.listDisplayTitle
                        let titleSuggestion = String(entry.listDisplayTitle.prefix(40))

                        switch pickerTarget {
                        case .newSnippet:
                            newSnippetContent = text
                            if newSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                newSnippetTitle = titleSuggestion
                            }
                        case .editSnippet:
                            editSnippetContent = text
                            if editSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                editSnippetTitle = titleSuggestion
                            }
                        }
                        model.notice = "Imported from Clipboard"
                        clipboardPickerTarget = nil
                    },
                    onDismiss: {
                        clipboardPickerTarget = nil
                    }
                )
            }
        }
    }

    private func actionLink(_ key: L10nKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(L10n.t(key))
                Image(systemName: "chevron.right").font(.system(size: 10))
            }
            .font(AppFont.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(AppColor.accent)
    }

    private func folderSection(_ folder: SnippetFolder) -> some View {
        let isExpanded = expandedFolderIDs.contains(folder.id)
        return VStack(spacing: 0) {
            // Folder header row
            if editingFolderId == folder.id {
                HStack(spacing: 6) {
                    TextField("Folder name", text: $editFolderTitle)
                        .textFieldStyle(.plain)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    Button(L10n.t(.save)) {
                        let trimmed = editFolderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            SnippetManager.shared.updateFolderTitle(id: folder.id, title: trimmed)
                            model.folders = SnippetManager.shared.folders
                        }
                        editingFolderId = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    Button("Cancel") { editingFolderId = nil }
                        .buttonStyle(.plain)
                        .font(AppFont.caption)
                }
                .padding(8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            if isExpanded { expandedFolderIDs.remove(folder.id) }
                            else { expandedFolderIDs.insert(folder.id) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isExpanded ? "folder.fill" : "folder")
                                .foregroundStyle(AppColor.accent)
                                .font(.system(size: 14))
                            Text(folder.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            Text("\(snippetsForFolder(folder).count)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.05), in: Capsule())
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    // Folder actions
                    HStack(spacing: 5) {
                        Button {
                            withAnimation {
                                expandedFolderIDs.insert(folder.id)
                                addingSnippetFolderId = folder.id
                                newSnippetTitle = ""
                                newSnippetContent = ""
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 22, height: 22)
                                .background(AppColor.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColor.accent)
                        .help("Add Snippet to this folder")

                        Button {
                            editFolderTitle = folder.title
                            editingFolderId = folder.id
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Rename Folder")

                        Button {
                            deleteTarget = DeleteTarget(isFolder: true, folderId: folder.id, snippetId: nil, name: folder.title)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("Delete Folder")

                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isExpanded { expandedFolderIDs.remove(folder.id) }
                                else { expandedFolderIDs.insert(folder.id) }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                                .frame(width: 18, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            // Sub-snippets list (expanded downwards)
            if isExpanded {
                VStack(spacing: 3) {
                    // Inline add snippet form
                    if addingSnippetFolderId == folder.id {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("New Snippet in \(folder.title)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("Snippet Headline / Title", text: $newSnippetTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12.5))
                                .padding(6)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

                            HStack {
                                Text("Content")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    clipboardPickerTarget = .newSnippet
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.clipboard")
                                            .font(.system(size: 10, weight: .medium))
                                        Text("From Clipboard")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(AppColor.accent.opacity(0.12), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(AppColor.accent)
                                .help("Pick an item from clipboard history to paste here")
                            }

                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $newSnippetContent)
                                    .font(.system(size: 12))
                                    .frame(height: 55)
                                    .padding(4)
                                    .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

                                if newSnippetContent.isEmpty {
                                    Text("Type content or click 'From Clipboard' above...")
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                        .padding(8)
                                        .allowsHitTesting(false)
                                }
                            }
                            HStack {
                                Spacer()
                                Button("Cancel") { addingSnippetFolderId = nil }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                Button(L10n.t(.save)) {
                                    let title = newSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !title.isEmpty {
                                        SnippetManager.shared.addSnippet(to: folder.id, title: title, content: newSnippetContent)
                                        model.folders = SnippetManager.shared.folders
                                        addingSnippetFolderId = nil
                                        newSnippetTitle = ""
                                        newSnippetContent = ""
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(newSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                        .padding(.top, 4)
                    }

                    let displayedSnippets = snippetsForFolder(folder)
                    if displayedSnippets.isEmpty && addingSnippetFolderId != folder.id {
                        Text(L10n.t(.noSnippets))
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(8)
                    } else {
                        ForEach(displayedSnippets) { snippet in
                            snippetRow(folder: folder, snippet: snippet)
                        }
                    }
                }
                .padding(.leading, 12)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func snippetRow(folder: SnippetFolder, snippet: Snippet) -> some View {
        if editingSnippetId == snippet.id {
            snippetEditView(snippet: snippet)
        } else {
            snippetDisplayRow(folder: folder, snippet: snippet)
        }
    }

    private func snippetEditView(snippet: Snippet) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("Title", text: $editSnippetTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

            HStack {
                Text("Content")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    clipboardPickerTarget = .editSnippet
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 10, weight: .medium))
                        Text("From Clipboard")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.accent.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColor.accent)
                .help("Pick an item from clipboard history to paste here")
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $editSnippetContent)
                    .font(.system(size: 12))
                    .frame(height: 55)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))

                if editSnippetContent.isEmpty {
                    Text("Type content or click 'From Clipboard' above...")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(8)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { editingSnippetId = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                Button(L10n.t(.save)) {
                    let title = editSnippetTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !title.isEmpty {
                        SnippetManager.shared.updateSnippetTitle(id: snippet.id, title: title)
                        SnippetManager.shared.updateSnippetContent(id: snippet.id, content: editSnippetContent)
                        model.folders = SnippetManager.shared.folders
                    }
                    editingSnippetId = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func snippetDisplayRow(folder: SnippetFolder, snippet: Snippet) -> some View {
        HStack(spacing: 8) {
            Button {
                model.onSnippet?(snippet.id)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(snippet.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                        if let dev = snippet.deviceName, dev.lowercased() != "mac" {
                            Text(dev)
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color.purple)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(snippet.content)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Action buttons
            HStack(spacing: 4) {
                Button {
                    editSnippetTitle = snippet.title
                    editSnippetContent = snippet.content
                    editingSnippetId = snippet.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Edit Snippet")

                Button {
                    deleteTarget = DeleteTarget(isFolder: false, folderId: folder.id, snippetId: snippet.id, name: snippet.title)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red.opacity(0.8))
                        .frame(width: 22, height: 22)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Delete Snippet")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .contentShape(Rectangle())
        .onHover { isHovered in
            let entry = HistoryEntry(
                item: .text(snippet.content),
                date: Date(),
                sourceApp: snippet.title,
                contentHash: snippet.id.uuidString
            )
            if isHovered {
                model.hoverRow(entry)
            } else {
                model.unhoverRow(entry)
            }
        }
    }
}

private struct SnippetClipboardPickerSheet: View {
    let onSelect: (HistoryEntry) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var entries: [HistoryEntry] = []
    @State private var hoveredId: String?
    @FocusState private var isSearchFocused: Bool

    private var filteredEntries: [HistoryEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return entries }
        return entries.filter { entry in
            let text = entry.resolvedText ?? ClipboardManager.shared.plainText(for: entry.item) ?? entry.listDisplayTitle
            let app = entry.sourceApp ?? ""
            return text.localizedCaseInsensitiveContains(trimmed) || app.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 8) {
                // Header
                HStack(alignment: .center) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard.fill")
                            .foregroundStyle(AppColor.accent)
                            .font(.system(size: 14))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Clipboard History")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Click an item to insert into snippet")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    TextField("Search clipboard history...", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .focused($isSearchFocused)
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                .padding(.horizontal, 10)

                // Items list
                ScrollView {
                    if filteredEntries.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 24, weight: .ultraLight))
                                .foregroundStyle(.tertiary)
                            Text(query.isEmpty ? "Clipboard is empty" : "No matching items found")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .padding(25)
                        .frame(maxWidth: .infinity)
                    } else {
                        LazyVStack(spacing: 3) {
                            ForEach(filteredEntries) { entry in
                                pickerRow(entry)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxHeight: 230)
            }
            .frame(maxWidth: 330)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75))
            .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 8)
        }
        .onAppear {
            entries = ClipboardManager.shared.searchHistory(options: SearchHistoryOptions(browseLimit: 50)).map(\.entry)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFocused = true
            }
        }
    }

    private func pickerRow(_ entry: HistoryEntry) -> some View {
        let text = entry.resolvedText ?? ClipboardManager.shared.plainText(for: entry.item) ?? entry.item.fileURLs?.map(\.path).joined(separator: "\n") ?? entry.listDisplayTitle
        let isHovered = hoveredId == entry.id

        return Button {
            onSelect(entry)
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        if let source = entry.sourceApp, !source.isEmpty {
                            Text(source)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(AppColor.accent)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(AppColor.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                        Text(RelativeTimeFormatter.string(from: entry.date))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                        if isHovered {
                            Text("Insert")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(AppColor.accent, in: Capsule())
                        }
                    }
                    Text(entry.listDisplayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    if text != entry.listDisplayTitle && !text.isEmpty {
                        Text(text)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(6)
            .contentShape(Rectangle())
            .background(isHovered ? AppColor.accent.opacity(0.09) : Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in
            if h { hoveredId = entry.id }
            else if hoveredId == entry.id { hoveredId = nil }
        }
    }
}

func exportHistoryImageAsJPG(path: String, completion: ((String?) -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
        guard let data = HistoryMediaStore.shared.data(at: path) ?? (try? Data(contentsOf: URL(fileURLWithPath: path))),
              let nsImage = NSImage(data: data) else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpgData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.95]) else {
            DispatchQueue.main.async { completion?(nil) }
            return
        }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "Techuboard_\(df.string(from: Date())).jpg"
        let destination = downloads.appendingPathComponent(filename)

        do {
            try jpgData.write(to: destination)
            DispatchQueue.main.async {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
                completion?(filename)
            }
        } catch {
            DispatchQueue.main.async { completion?(nil) }
        }
    }
}

struct MenuBarSidePreviewView: View {
    let entry: HistoryEntry
    var onHoverChanged: ((Bool) -> Void)? = nil
    @State private var downloadedName: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            HistoryPreviewView(entry: entry, transparentBackground: true)

            if case .image(let path) = entry.item {
                Button {
                    exportHistoryImageAsJPG(path: path) { name in
                        downloadedName = name
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            downloadedName = nil
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: downloadedName != nil ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text(downloadedName != nil ? "Saved to Downloads" : "Download JPG")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                    .foregroundStyle(AppColor.accent)
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .padding(12)
                .help("Download high-resolution JPG to Downloads folder")
            }
        }
        .macGlassSurface(cornerRadius: 16)
        .onHover { isHovered in
            onHoverChanged?(isHovered)
        }
    }
}
