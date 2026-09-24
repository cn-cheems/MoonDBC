///|
using @rabbita {type Cmd, type Emit, type Html, type Val, none, perform}

///|
using @html {button, div, h1, h2, input, label, nothing, p, span, textarea}

///|
let max_import_bytes : Int = 4 * 1024 * 1024

///|
extern "js" fn selected_file_name(input_id : String) -> String = "(inputId) => document.getElementById(inputId)?.files?.[0]?.name ?? ''"

///|
extern "js" fn selected_file_size(input_id : String) -> Int = "(inputId) => document.getElementById(inputId)?.files?.[0]?.size ?? -1"

///|
extern "js" fn selected_file_text(input_id : String) -> @js.Promise =
  #| (inputId) => {
  #|   const file = document.getElementById(inputId)?.files?.[0];
  #|   return file ? file.text() : Promise.reject(new Error("No file selected"));
  #| }

///|
extern "js" fn clear_selected_file(input_id : String) -> Unit =
  #| (inputId) => {
  #|   const input = document.getElementById(inputId);
  #|   if (input) input.value = "";
  #| }

///|
let sample_dbc =
  #|VERSION "MoonDBC Workbench"
  #|
  #|NS_ :
  #|
  #|BS_:
  #|
  #|BU_: ECU Display Sensor
  #|
  #|BO_ 256 Powertrain: 8 ECU
  #| SG_ EngineSpeed : 0|16@1+ (0.25,0) [0|16000] "rpm" Display
  #| SG_ CoolantTemp : 16|8@1- (1,-40) [-40|215] "degC" Display
  #| SG_ Gear : 24|4@1+ (1,0) [0|15] "" Display
  #|
  #|BO_ 512 SensorData: 8 Sensor
  #| SG_ Mode M : 0|4@1+ (1,0) [0|15] "" Display
  #| SG_ Voltage m1 : 8|16@1+ (0.01,0) [0|655.35] "V" Display
  #| SG_ Current m2 : 8|16@1+ (0.01,0) [0|655.35] "A" Display
  #|

///|
struct Model {
  source : String
  selected_message : Int
  source_name : String
  source_bytes : Int?
  importing : Bool
  import_error : String?
} derive(Eq)

///|
enum Msg {
  SourceChanged(String)
  SelectMessage(Int)
  LoadSample
  FilePicked
  FileReadFinished(FileReadResult)
}

///|
enum FileReadResult {
  FileReadSuccess(String, String, Int)
  FileReadFailure(String)
}

///|
fn validate_import_metadata(name : String, size : Int) -> String? {
  if name == "" || size < 0 {
    Some("No file was selected.")
  } else if !name.to_lower().has_suffix(".dbc") {
    Some("Choose a file with the .dbc extension.")
  } else if size > max_import_bytes {
    Some("The file exceeds the 4 MiB import limit.")
  } else {
    None
  }
}

///|
fn read_selected_file_command(
  send : Emit[Msg],
  name : String,
  size : Int,
) -> Cmd {
  perform(result => send(FileReadFinished(result)), async fn() noraise {
    let result = try
      selected_file_text("dbc-file-input").wait().to_string()
    catch {
      _ => FileReadFailure("The selected file could not be read as text.")
    } noraise {
      source => FileReadSuccess(name, source, size)
    }
    clear_selected_file("dbc-file-input")
    result
  })
}

///|
fn source_size_label(model : Model) -> String {
  match model.source_bytes {
    Some(bytes) if bytes < 1024 => "\{bytes} bytes"
    Some(bytes) => "\{(bytes + 1023) / 1024} KiB"
    None => "\{model.source.length()} characters"
  }
}

///|
fn import_status_view(model : Model) -> Html {
  if model.importing {
    div(class="import-status is-loading", "Reading local file…")
  } else {
    match model.import_error {
      Some(message) => div(class="import-status is-error", message)
      None =>
        div(class="source-meta", [
          span(model.source_name),
          span(source_size_label(model)),
        ])
    }
  }
}

///|
fn span_label(source : @moondbc.SourceSpan?) -> String {
  match source {
    Some(span) => "line \{span.start_line}:\{span.start_column}"
    None => "generated model"
  }
}

///|
fn byte_order_label(order : @moondbc.ByteOrder) -> String {
  match order {
    @moondbc.Intel => "Intel"
    @moondbc.Motorola => "Motorola"
  }
}

///|
fn value_type_label(value_type : @moondbc.SignalValueType) -> String {
  match value_type {
    @moondbc.Integer => "integer"
    @moondbc.Float32 => "float32"
    @moondbc.Float64 => "float64"
  }
}

///|
fn multiplex_label(role : @moondbc.MultiplexRole) -> String {
  match role {
    @moondbc.Plain => "plain"
    @moondbc.Multiplexer => "selector"
    @moondbc.Multiplexed(value) => "mux \{value}"
  }
}

///|
fn layout_cell_class(kind : @moondbc.FrameLayoutCellKind) -> String {
  match kind {
    @moondbc.LayoutUnused => "bit-cell is-unused"
    @moondbc.LayoutOccupied => "bit-cell is-occupied"
    @moondbc.LayoutMultiplexed => "bit-cell is-multiplexed"
    @moondbc.LayoutConflict => "bit-cell is-conflict"
  }
}

///|
fn owner_label(cell : @moondbc.FrameLayoutCell) -> String {
  if cell.owners.is_empty() {
    "free"
  } else if cell.owners.length() == 1 {
    cell.owners[0].signal_name
  } else {
    let names : Array[String] = []
    for owner in cell.owners {
      names.push(owner.signal_name)
    }
    names.join(" / ")
  }
}

///|
fn layout_issue_label(issue : @moondbc.FrameLayoutIssue) -> String {
  match issue {
    @moondbc.LayoutInvalidPayloadSize(size) =>
      "payload size \{size} is outside the supported range"
    @moondbc.LayoutInvalidSignal(name, start, length, source) =>
      "\{name}: invalid bit range \{start}|\{length} (\{span_label(source)})"
    @moondbc.LayoutSignalOutsidePayload(name, source) =>
      "\{name}: signal exceeds the payload (\{span_label(source)})"
    @moondbc.LayoutConflictingSignals(
      left,
      right,
      bits,
      left_source,
      right_source
    ) => {
      let positions = bits.map(bit => bit.to_string()).join(", ")
      "\{left} and \{right} overlap at bits \{positions} (\{span_label(left_source)} / \{span_label(right_source)})"
    }
  }
}

///|
fn metric(label : String, value : String) -> Html {
  div(class="metric", [
    span(class="metric-value", value),
    span(class="metric-label", label),
  ])
}

///|
fn diagnostics_view(result : @moondbc.SourceParseResult) -> Html {
  if result.diagnostics.is_empty() {
    div(class="status-card is-valid", [
      span(class="status-dot", ""),
      div([
        span(class="status-title", "DBC syntax is valid"),
        p("Source locations and semantic model are ready."),
      ]),
    ])
  } else {
    div(class="diagnostics", [
      div(class="status-card is-invalid", [
        span(class="status-dot", ""),
        div([
          span(
            class="status-title",
            "\{result.diagnostics.length()} parser issue(s)",
          ),
          p("Fix the source lines below before using the decoded model."),
        ]),
      ]),
      div(
        class="diagnostic-list",
        result.diagnostics.map(diagnostic => {
          div(class="diagnostic-row", [
            span(class="diagnostic-code", diagnostic.code),
            div([
              p(class="diagnostic-message", diagnostic.message),
              span(
                class="source-position",
                "line \{diagnostic.line}:\{diagnostic.column}",
              ),
            ]),
          ])
        }),
      ),
    ])
  }
}

///|
fn message_button(
  message : @moondbc.Message,
  index : Int,
  selected : Int,
  emit : Emit[Msg],
) -> Html {
  let class = if index == selected {
    "message-item is-active"
  } else {
    "message-item"
  }
  button(type_="button", class~, on_click=emit(SelectMessage(index)), [
    div(class="message-item-main", [
      span(class="message-name", message.name),
      span(class="message-id", "ID \{message.frame_id()}"),
    ]),
    div(class="message-item-meta", [
      span("\{message.payload_size} bytes"),
      span("\{message.signals.length()} signals"),
    ]),
  ])
}

///|
fn message_buttons(
  messages : Array[@moondbc.Message],
  selected : Int,
  emit : Emit[Msg],
) -> Array[Html] {
  let items : Array[Html] = []
  for index, message in messages {
    items.push(message_button(message, index, selected, emit))
  }
  items
}

///|
fn signal_card(
  message : @moondbc.Message,
  signal : @moondbc.Signal,
  source_map : @moondbc.DbcSourceMap,
) -> Html {
  let source = source_map.find_signal(message.id, signal.name)
  div(class="signal-card", [
    div(class="signal-heading", [
      span(class="signal-name", signal.name),
      span(class="source-position", span_label(source)),
    ]),
    div(class="signal-facts", [
      span("bit \{signal.start_bit}|\{signal.bit_length}"),
      span(byte_order_label(signal.byte_order)),
      span(value_type_label(signal.value_type)),
      span(multiplex_label(signal.multiplex)),
    ]),
    p(
      class="signal-scale",
      "physical = raw × \{signal.factor} + \{signal.offset} \{signal.unit}",
    ),
  ])
}

///|
fn bit_cell(cell : @moondbc.FrameLayoutCell) -> Html {
  div(class=layout_cell_class(cell.kind), [
    span(class="bit-number", cell.bit_in_byte.to_string()),
    span(class="bit-owner", owner_label(cell)),
  ])
}

///|
fn byte_row(layout : @moondbc.FrameLayoutAnalysis, byte_index : Int) -> Html {
  let cells : Array[Html] = []
  for display_index = 0; display_index < 8; display_index = display_index + 1 {
    let bit_index = 7 - display_index
    match layout.find_cell(byte_index, bit_index) {
      Some(cell) => cells.push(bit_cell(cell))
      None => ()
    }
  }
  div(class="byte-row", [
    div(class="byte-label", [span("BYTE"), span(byte_index.to_string())]),
    div(class="byte-bits", cells),
  ])
}

///|
fn layout_view(
  result : @moondbc.SourceParseResult,
  message : @moondbc.Message,
) -> Html {
  match result.analyze_frame_layout(message.id) {
    Err(_) =>
      div(class="empty-panel", "Layout is unavailable for this message.")
    Ok(layout) => {
      let rows : Array[Html] = []
      for byte_index = 0
          byte_index < layout.payload_size
          byte_index = byte_index + 1 {
        rows.push(byte_row(layout, byte_index))
      }
      let issue_panel = if layout.issues.is_empty() {
        div(class="layout-status is-clear", "No layout conflicts")
      } else {
        div(class="layout-issues", [
          div(
            class="layout-status is-warning",
            "\{layout.issues.length()} layout issue(s)",
          ),
          div(
            class="layout-issue-list",
            layout.issues.map(issue => p(layout_issue_label(issue))),
          ),
        ])
      }
      div(class="layout-panel", [
        div(class="legend", [
          span(class="legend-item occupied", "occupied"),
          span(class="legend-item multiplexed", "multiplexed"),
          span(class="legend-item conflict", "conflict"),
          span(class="legend-item unused", "free"),
        ]),
        issue_panel,
        div(class="byte-table", rows),
      ])
    }
  }
}

///|
fn message_detail(
  result : @moondbc.SourceParseResult,
  selected_message : Int,
) -> Html {
  if result.database.messages.is_empty() {
    div(class="empty-panel", [
      h2("No messages yet"),
      p("Paste a DBC definition to inspect its messages and signals."),
    ])
  } else {
    let selected = if selected_message >= 0 &&
      selected_message < result.database.messages.length() {
      selected_message
    } else {
      0
    }
    let message = result.database.messages[selected]
    let source = result.source_map.find_message(message.id)
    div(class="detail-stack", [
      div(class="detail-header", [
        div([
          span(class="eyebrow", "SELECTED MESSAGE"),
          h2(message.name),
          p(
            class="detail-subtitle",
            "\{span_label(source)} · transmitter \{message.transmitter}",
          ),
        ]),
        div(class="detail-metrics", [
          metric("CAN ID", message.frame_id().to_string()),
          metric("PAYLOAD", "\{message.payload_size} B"),
          metric("SIGNALS", message.signals.length().to_string()),
        ]),
      ]),
      div(class="section-heading", [
        div([
          h2("Frame layout"),
          p("Bits are shown from 7 to 0 for each payload byte."),
        ]),
      ]),
      layout_view(result, message),
      div(class="section-heading", [
        div([
          h2("Signals"),
          p("Storage, scaling and source position from the parsed model."),
        ]),
      ]),
      div(
        class="signal-grid",
        message.signals.map(signal => {
          signal_card(message, signal, result.source_map)
        }),
      ),
    ])
  }
}

///|
fn workbench_view(model : Model, emit : Emit[Msg]) -> Html {
  let result = @moondbc.parse_with_source_map(model.source)
  let signal_count = result.database.messages.fold(init=0, (count, message) => {
    count + message.signals.length()
  })
  div(class="workbench", [
    div(class="topbar", [
      div(class="brand", [
        span(class="brand-mark", "M"),
        div([
          h1("MoonDBC Workbench"),
          p("Inspect DBC structure and CAN frame layouts in the browser."),
        ]),
      ]),
      span(class="runtime-badge", "MoonBit · local only"),
    ]),
    div(class="summary-strip", [
      metric("MESSAGES", result.database.messages.length().to_string()),
      metric("SIGNALS", signal_count.to_string()),
      metric("DIAGNOSTICS", result.diagnostics.length().to_string()),
      metric("NODES", result.database.nodes.length().to_string()),
    ]),
    div(class="workspace-grid", [
      div(class="source-column", [
        div(class="panel-heading", [
          div([span(class="eyebrow", "LOCAL SOURCE"), h2("DBC input")]),
          div(class="source-actions", [
            label(class="import-button", [
              span("Open .dbc"),
              input(
                input_type=File,
                id="dbc-file-input",
                class="file-input",
                accept=".dbc,text/plain",
                on_change=emit.map(_ => FilePicked),
              ),
            ]),
            button(
              type_="button",
              class="secondary-button",
              on_click=emit(LoadSample),
              "Load sample",
            ),
          ]),
        ]),
        textarea(
          class="source-editor",
          value=model.source,
          on_input=emit.map(source => SourceChanged(source)),
          placeholder="Paste DBC text here…",
          nothing,
        ),
        import_status_view(model),
        diagnostics_view(result),
      ]),
      div(class="message-column", [
        div(class="panel-heading", [
          div([span(class="eyebrow", "DATABASE"), h2("Messages")]),
          span(
            class="panel-count",
            result.database.messages.length().to_string(),
          ),
        ]),
        div(
          class="message-list",
          message_buttons(
            result.database.messages,
            model.selected_message,
            emit,
          ),
        ),
      ]),
      div(class="detail-column", message_detail(result, model.selected_message)),
    ]),
  ])
}

///|
fn app() -> Val[Html] {
  let (model, emit) = @rabbita.create_state(
    {
      source: sample_dbc,
      selected_message: 0,
      source_name: "sample.dbc",
      source_bytes: None,
      importing: false,
      import_error: None,
    },
    update=fn(send, msg, model) {
      let (next, command) = match msg {
        SourceChanged(source) =>
          (
            {
              ..model,
              source,
              selected_message: 0,
              source_name: "Manual input",
              source_bytes: None,
              import_error: None,
            },
            none,
          )
        SelectMessage(selected_message) =>
          ({ ..model, selected_message, }, none)
        LoadSample =>
          (
            {
              source: sample_dbc,
              selected_message: 0,
              source_name: "sample.dbc",
              source_bytes: None,
              importing: false,
              import_error: None,
            },
            none,
          )
        FilePicked => {
          let name = selected_file_name("dbc-file-input")
          let size = selected_file_size("dbc-file-input")
          match validate_import_metadata(name, size) {
            Some(message) => {
              clear_selected_file("dbc-file-input")
              (
                { ..model, importing: false, import_error: Some(message), },
                none,
              )
            }
            None =>
              (
                { ..model, importing: true, import_error: None, },
                read_selected_file_command(send, name, size),
              )
          }
        }
        FileReadFinished(result) =>
          match result {
            FileReadSuccess(name, source, size) =>
              (
                {
                  source,
                  selected_message: 0,
                  source_name: name,
                  source_bytes: Some(size),
                  importing: false,
                  import_error: None,
                },
                none,
              )
            FileReadFailure(message) =>
              (
                { ..model, importing: false, import_error: Some(message), },
                none,
              )
          }
      }
      (next, command)
    },
  )
  model.map(model => workbench_view(model, emit))
}

///|
fn main {
  @rabbita.new(app).mount("app")
}
