import SwiftUI
import MarauderCore

struct WorkflowsView: View {
    @EnvironmentObject var model: AppModel
    @State private var search = ""
    @State private var category = "All workflows"
    @State private var showImport = false
    private let columns = [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)]
    private var visibleWorkflows: [Workflow] {
        Workflow.catalog.filter {
            (category == "All workflows" || $0.category.rawValue == category) &&
            (search.isEmpty || ($0.name + " " + $0.summary).localizedCaseInsensitiveContains(search))
        }
    }
    var body: some View {
        Group {
            if model.workflowDetailVisible { detail }
            else { gallery }
        }.sheet(isPresented: $showImport) { TargetImportView() }
    }
    private var gallery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    SectionHeader(title: "What would you like to do?", subtitle: "Choose a workflow. Read the guide, then start each step when you’re ready.")
                    Spacer(minLength: 16)
                    Button("Paste a network", systemImage: "doc.on.clipboard") { showImport = true }.buttonStyle(.bordered).disabled(model.automationRunning)
                }
                if model.importedTarget != nil { TargetPlanView() }
                HStack(spacing: 14) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Find a workflow", text: $search).textFieldStyle(.plain)
                    }.padding(9).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                    Picker("Show", selection: $category) {
                        Text("All workflows").tag("All workflows")
                        ForEach(WorkflowCategory.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
                    }.frame(width: 245)
                }
                if !model.canSend {
                    HStack(spacing: 10) {
                        Image(systemName: "cable.connector").foregroundStyle(.orange)
                        Text("You can read every guide now. Connect your Flipper or open the demo to run steps.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Connection") { model.destination = .connection }
                    }.padding(14).background(Color.orange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(WorkflowCategory.allCases, id: \.self) { group in
                    let workflows = visibleWorkflows.filter { $0.category == group }
                    if !workflows.isEmpty {
                        Text(group.rawValue).font(.title3.weight(.semibold)).padding(.top, 2)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                            ForEach(workflows) { workflow in workflowCard(workflow) }
                        }
                    }
                }
                if visibleWorkflows.isEmpty { ContentUnavailableView.search(text: search) }
            }.padding(24)
        }
    }
    private func workflowCard(_ workflow: Workflow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: workflow.symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(.orange)
                    .frame(width: 46, height: 46).background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Text("\(workflow.steps.count) \(workflow.steps.count == 1 ? "step" : "steps")")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.quaternary.opacity(0.3), in: Capsule())
            }
            Text(workflow.name).font(.system(size: 17, weight: .semibold))
            Text(workflow.summary).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Text("START HERE").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(.secondary)
                Text(workflow.guide.start).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            HStack {
                if workflow.activeTransmission { Label("Transmits traffic", systemImage: "antenna.radiowaves.left.and.right").font(.caption2).foregroundStyle(.orange) }
                Spacer()
                Button {
                    model.selectedWorkflow = workflow.id; model.changeWorkflow(); model.workflowDetailVisible = true
                } label: { HStack { Text("View guide"); Image(systemName: "arrow.right") } }
                    .buttonStyle(.bordered).controlSize(.regular)
            }
        }.padding(20).frame(maxWidth: .infinity, minHeight: 270, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.quaternary))
    }
    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Button { model.workflowDetailVisible = false } label: { Label("All workflows", systemImage: "arrow.left") }.buttonStyle(.borderless)
                    Spacer()
                    Text(model.workflow.category.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: model.workflow.symbol).font(.system(size: 28)).foregroundStyle(.orange)
                        .frame(width: 58, height: 58).background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    SectionHeader(title: model.workflow.name, subtitle: model.workflow.summary)
                    Spacer()
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), alignment: .top)], alignment: .leading, spacing: 12) {
                    guideBlock("Before you start", "1.circle", model.workflow.guide.start)
                    guideBlock("What to look for", "eye", model.workflow.guide.expected)
                    guideBlock("When you’re done", "arrow.turn.down.right", model.workflow.guide.next)
                }
                if model.workflow.activeTransmission {
                    Label("This workflow sends wireless traffic and can affect connectivity. Review the selected network before starting.", systemImage: "antenna.radiowaves.left.and.right")
                        .font(.callout).foregroundStyle(.orange)
                }
                if !model.workflow.fields.isEmpty { parameters }
                HStack {
                    Text("Step by step").font(.title3.weight(.semibold))
                    Spacer()
                    Text("\(model.completedSteps.count) of \(model.workflow.steps.count) sent").font(.caption).foregroundStyle(.secondary)
                }
                Text("Send a step, check its response in the terminal, then continue. Sending a command does not confirm that the firmware completed it.")
                    .font(.callout).foregroundStyle(.secondary)
                if !model.canSend {
                    HStack { Label("Connect your Flipper to start", systemImage: "cable.connector"); Spacer(); Button("Open connection") { model.destination = .connection } }
                        .font(.callout).padding(14).background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(model.workflow.steps) { step in stepView(step) }
                HStack {
                    Button("Reset progress", systemImage: "arrow.counterclockwise") { model.changeWorkflow() }
                    Spacer()
                    if let nextID = model.workflow.guide.nextWorkflow, let next = Workflow.catalog.first(where: { $0.id == nextID }) {
                        Button("Next: \(next.name)", systemImage: "arrow.right") {
                            model.selectedWorkflow = nextID; model.changeWorkflow()
                        }.buttonStyle(.bordered)
                    }
                }
            }.padding(24)
        }.id(model.selectedWorkflow)
    }
    private func guideBlock(_ title: String, _ icon: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon).font(.callout.weight(.semibold)).foregroundStyle(.orange)
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }
    private var parameters: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Fill these after discovery. AP and station indices come from the device’s lists.").font(.caption).foregroundStyle(.secondary)
                ForEach(model.workflow.fields) { field in
                    HStack {
                        Text(field.label).font(.callout).frame(width: 130, alignment: .leading)
                        TextField(field.placeholder, text: Binding(get: { model.workflowValues[field.id] ?? "" }, set: { model.workflowValues[field.id] = $0 }))
                            .textFieldStyle(.roundedBorder).font(.system(.body, design: .monospaced))
                    }
                }
                if model.workflow.fields.contains(where: { $0.id == "targets" }) {
                    Button("Use selected networks", systemImage: "checkmark.circle") { model.useSelectedIndices() }.disabled(model.selectedNetworks.isEmpty)
                }
            }.padding(12)
        } label: { Text("Your parameters") }
    }
    private func stepView(_ step: WorkflowStep) -> some View {
        let rendered = try? model.workflow.render(step, values: model.workflowValues, modern: model.modernFirmware)
        let isSent = model.completedSteps.contains(step.id)
        return HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(isSent ? Color.green.opacity(0.12) : Color.orange.opacity(0.10)).frame(width: 32, height: 32)
                if isSent { Image(systemName: "arrow.up").foregroundStyle(.green).font(.caption.weight(.bold)) }
                else { Text("\(step.id + 1)").font(.callout.weight(.bold)).foregroundStyle(.orange) }
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(step.title).font(.headline)
                    Spacer()
                    if isSent { Text("Sent").font(.caption).foregroundStyle(.secondary) }
                    Button(isSent ? "Send again" : "Start step") { model.sendWorkflowStep(step) }
                        .buttonStyle(.bordered).disabled(!model.canSend || rendered == nil || step.id > model.workflowCursor)
                }
                Text(step.guidance).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(rendered ?? step.command).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                if rendered == nil { Text("Fill in the parameters above to enable this step.").font(.caption).foregroundStyle(.orange) }
            }
        }.padding(18).background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(step.id == model.workflowCursor ? Color.orange.opacity(0.45) : Color.secondary.opacity(0.15)))
    }
}
