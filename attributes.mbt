///|
fn attribute_statement_body(
  line : StringView,
  prefix_length : Int,
) -> Result[StringView, String] {
  let body = line[prefix_length:].trim()
  if !body.has_suffix(";") {
    Err("attribute declaration is missing ';'")
  } else {
    Ok(body[:body.length() - 1].trim())
  }
}

///|
fn attribute_name_and_tail(
  content : StringView,
) -> Result[(String, StringView, StringView), String] {
  let open_quote = match content.find("\"") {
    Some(value) => value
    None => return Err("attribute name is missing an opening quote")
  }
  let close_quote = match find_after(content, open_quote + 1, "\"") {
    Some(value) => value
    None => return Err("attribute name is missing a closing quote")
  }
  let name = content[open_quote + 1:close_quote]
  if name.is_empty() || name.contains("\\") {
    return Err("attribute name is empty or contains an escape")
  }
  Ok(
    (
      name.to_owned(),
      content[:open_quote].trim(),
      content[close_quote + 1:].trim(),
    ),
  )
}

///|
fn attribute_type_from_text(
  text : StringView,
) -> Result[DbcAttributeType, String] {
  let fields = words(text)
  if fields.is_empty() {
    return Err("attribute type is missing")
  }
  match fields[0] {
    "INT" | "HEX" => {
      if fields.length() != 3 {
        return Err("integer attribute type requires minimum and maximum")
      }
      let minimum = match parse_int64(fields[1]) {
        Some(value) => value
        None => return Err("integer attribute minimum is invalid")
      }
      let maximum = match parse_int64(fields[2]) {
        Some(value) if value >= minimum => value
        _ => return Err("integer attribute maximum is invalid")
      }
      if fields[0] == "INT" {
        Ok(AttributeIntegerType(minimum, maximum))
      } else {
        Ok(AttributeHexType(minimum, maximum))
      }
    }
    "FLOAT" => {
      if fields.length() != 3 {
        return Err("floating attribute type requires minimum and maximum")
      }
      let minimum = match parse_double(fields[1]) {
        Some(value) if !value.is_nan() && !value.is_inf() => value
        _ => return Err("floating attribute minimum is invalid")
      }
      let maximum = match parse_double(fields[2]) {
        Some(value) if !value.is_nan() && !value.is_inf() && value >= minimum =>
          value
        _ => return Err("floating attribute maximum is invalid")
      }
      Ok(AttributeFloatType(minimum, maximum))
    }
    "STRING" =>
      if fields.length() == 1 {
        Ok(AttributeStringType)
      } else {
        Err("string attribute type has unexpected fields")
      }
    "ENUM" => {
      let choices : Array[String] = []
      let mut rest = text[4:].trim()
      while !rest.is_empty() {
        if !rest.has_prefix("\"") {
          return Err("enumeration choice must be quoted")
        }
        let mut search = 1
        let mut close_quote = -1
        while close_quote < 0 {
          let position = match find_after(rest, search, "\"") {
            Some(value) => value
            None => return Err("enumeration choice is missing a closing quote")
          }
          let mut escapes = 0
          let mut before = position - 1
          while before >= 1 && rest[before:before + 1] == "\\" {
            escapes += 1
            before -= 1
          }
          if escapes % 2 == 0 {
            close_quote = position
          } else {
            search = position + 1
          }
        }
        match parse_comment_text(rest[1:close_quote + 1]) {
          Ok(value) => choices.push(value)
          Err(_) => return Err("enumeration choice is invalid")
        }
        let trailing = rest[close_quote + 1:].trim()
        if trailing.is_empty() {
          rest = trailing
        } else if trailing.has_prefix(",") {
          rest = trailing[1:].trim()
          if rest.is_empty() {
            return Err("enumeration choice list ends with a comma")
          }
        } else {
          return Err("enumeration choices must be comma-separated")
        }
      }
      if choices.is_empty() {
        Err("enumeration attribute requires at least one choice")
      } else {
        Ok(AttributeEnumType(choices))
      }
    }
    _ => Err("unsupported attribute type")
  }
}

///|
fn parse_attribute_definition_line(
  line : StringView,
) -> Result[DbcAttributeDefinition, String] {
  let content = match attribute_statement_body(line, 7) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (name, scope_text, type_text) = match attribute_name_and_tail(content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let scope = match scope_text {
    "" => DatabaseAttributeScope
    "BU_" => NodeAttributeScope
    "BO_" => MessageAttributeScope
    "SG_" => SignalAttributeScope
    _ => return Err("attribute scope must be BU_, BO_, or SG_")
  }
  let value_type = match attribute_type_from_text(type_text) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  Ok({ name, scope, value_type, })
}

///|
fn parse_attribute_default_line(
  line : StringView,
) -> Result[(String, String), String] {
  let content = match attribute_statement_body(line, 11) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (name, prefix, raw_value) = match attribute_name_and_tail(content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !prefix.is_empty() || raw_value.is_empty() {
    return Err("attribute default requires a name and value")
  }
  Ok((name, raw_value.to_owned()))
}

///|
fn attribute_take_word(
  text : StringView,
) -> Result[(StringView, StringView), String] {
  let trimmed = text.trim()
  match trimmed.find(" ") {
    Some(index) => Ok((trimmed[:index], trimmed[index + 1:].trim()))
    None => Err("attribute target or value is incomplete")
  }
}

///|
fn parse_attribute_assignment_line(
  line : StringView,
) -> Result[(String, DbcAttributeTarget, String), String] {
  let content = match attribute_statement_body(line, 3) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let (name, prefix, tail) = match attribute_name_and_tail(content) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if !prefix.is_empty() || tail.is_empty() {
    return Err("attribute assignment requires a name and value")
  }
  let (target, raw_value) = if tail.has_prefix("BU_ ") {
    let (node, value) = match attribute_take_word(tail[4:]) {
      Ok(result) => result
      Err(error) => return Err(error)
    }
    (NodeAttributeTarget(node.to_owned()), value)
  } else if tail.has_prefix("BO_ ") {
    let (id_text, value) = match attribute_take_word(tail[4:]) {
      Ok(result) => result
      Err(error) => return Err(error)
    }
    let id = match parse_uint(id_text) {
      Some(value) if dbc_message_id_parts(value) is Some(_) => value
      _ => return Err("attribute message id is invalid")
    }
    (MessageAttributeTarget(id), value)
  } else if tail.has_prefix("SG_ ") {
    let (id_text, signal_and_value) = match attribute_take_word(tail[4:]) {
      Ok(result) => result
      Err(error) => return Err(error)
    }
    let id = match parse_uint(id_text) {
      Some(value) if dbc_message_id_parts(value) is Some(_) => value
      _ => return Err("attribute message id is invalid")
    }
    let (signal, value) = match attribute_take_word(signal_and_value) {
      Ok(result) => result
      Err(error) => return Err(error)
    }
    (SignalAttributeTarget(id, signal.to_owned()), value)
  } else {
    (DatabaseAttributeTarget, tail)
  }
  if raw_value.is_empty() {
    return Err("attribute assignment value is missing")
  }
  Ok((name, target, raw_value.to_owned()))
}

///|
fn attribute_value_from_text(
  raw : StringView,
  value_type : DbcAttributeType,
) -> Result[DbcAttributeValue, String] {
  match value_type {
    AttributeIntegerType(_, _) | AttributeHexType(_, _) =>
      match parse_int64(raw) {
        Some(value) => Ok(AttributeInteger(value))
        None => Err("attribute value is not an integer")
      }
    AttributeFloatType(_, _) =>
      match parse_double(raw) {
        Some(value) if !value.is_nan() && !value.is_inf() =>
          Ok(AttributeFloat(value))
        _ => Err("attribute value is not a finite number")
      }
    AttributeStringType =>
      if raw.has_prefix("\"") {
        match parse_comment_text(raw[1:]) {
          Ok(value) => Ok(AttributeText(value))
          Err(_) => Err("attribute string value is invalid")
        }
      } else {
        Err("attribute string value must be quoted")
      }
    AttributeEnumType(choices) =>
      if raw.has_prefix("\"") {
        match parse_comment_text(raw[1:]) {
          Ok(value) => {
            for choice in choices {
              if choice == value {
                return Ok(AttributeText(value))
              }
            }
            Err("attribute enum value is not a declared choice")
          }
          Err(_) => Err("attribute enum value is invalid")
        }
      } else {
        match parse_int64(raw) {
          Some(value) if value >= 0 && value < choices.length().to_int64() =>
            Ok(AttributeInteger(value))
          _ => Err("attribute enum index is invalid")
        }
      }
  }
}

///|
fn attribute_target_scope(target : DbcAttributeTarget) -> DbcAttributeScope {
  match target {
    DatabaseAttributeTarget => DatabaseAttributeScope
    NodeAttributeTarget(_) => NodeAttributeScope
    MessageAttributeTarget(_) => MessageAttributeScope
    SignalAttributeTarget(_, _) => SignalAttributeScope
  }
}

///|
fn attribute_target_exists(
  nodes : Array[String],
  messages : Array[Message],
  target : DbcAttributeTarget,
) -> Bool {
  match target {
    DatabaseAttributeTarget => true
    NodeAttributeTarget(node) => contains_node(nodes, node)
    MessageAttributeTarget(id) => find_message_index(messages, id) is Some(_)
    SignalAttributeTarget(id, signal_name) =>
      match find_message_index(messages, id) {
        Some(index) => contains_signal_name(messages[index], signal_name)
        None => false
      }
  }
}

///|
fn find_attribute_definition(
  definitions : Array[DbcAttributeDefinition],
  name : StringView,
) -> DbcAttributeDefinition? {
  for definition in definitions {
    if definition.name.view() == name {
      return Some(definition)
    }
  }
  None
}

///|
pub fn Database::attribute_value(
  self : Database,
  name : StringView,
  target : DbcAttributeTarget,
) -> DbcAttributeValue? {
  if !attribute_target_exists(self.nodes, self.messages, target) {
    return None
  }
  let definition = match
    find_attribute_definition(self.attributes.definitions, name) {
    Some(value) if value.scope == attribute_target_scope(target) => value
    _ => return None
  }
  for assignment in self.attributes.assignments {
    if assignment.name == definition.name && assignment.target == target {
      return Some(assignment.value)
    }
  }
  for default in self.attributes.defaults {
    if default.name == definition.name {
      return Some(default.value)
    }
  }
  None
}

///|
fn attribute_scope_text(scope : DbcAttributeScope) -> String {
  match scope {
    DatabaseAttributeScope => ""
    NodeAttributeScope => "BU_ "
    MessageAttributeScope => "BO_ "
    SignalAttributeScope => "SG_ "
  }
}

///|
fn attribute_type_text(
  value_type : DbcAttributeType,
) -> Result[String, DbcWriteError] {
  match value_type {
    AttributeIntegerType(minimum, maximum) =>
      if minimum <= maximum {
        Ok("INT \{minimum} \{maximum}")
      } else {
        Err(DbcWriteInvalidAttribute("integer bounds are reversed"))
      }
    AttributeHexType(minimum, maximum) =>
      if minimum <= maximum {
        Ok("HEX \{minimum} \{maximum}")
      } else {
        Err(DbcWriteInvalidAttribute("hexadecimal bounds are reversed"))
      }
    AttributeFloatType(minimum, maximum) =>
      if minimum.is_nan() ||
        minimum.is_inf() ||
        maximum.is_nan() ||
        maximum.is_inf() ||
        minimum > maximum {
        Err(DbcWriteInvalidAttribute("floating bounds are invalid"))
      } else {
        Ok("FLOAT \{minimum} \{maximum}")
      }
    AttributeStringType => Ok("STRING")
    AttributeEnumType(choices) => {
      if choices.is_empty() {
        return Err(DbcWriteInvalidAttribute("enumeration has no choices"))
      }
      let quoted : Array[String] = []
      for choice in choices {
        let escaped = match escape_dbc_comment(choice) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
        quoted.push("\"\{escaped}\"")
      }
      Ok("ENUM \{quoted.join(",")}")
    }
  }
}

///|
fn attribute_value_text(
  value : DbcAttributeValue,
  value_type : DbcAttributeType,
) -> Result[String, DbcWriteError] {
  match (value_type, value) {
    (AttributeIntegerType(_, _), AttributeInteger(number))
    | (AttributeHexType(_, _), AttributeInteger(number)) =>
      Ok(number.to_string())
    (AttributeFloatType(_, _), AttributeFloat(number)) =>
      if number.is_nan() || number.is_inf() {
        Err(DbcWriteInvalidAttribute("floating value is not finite"))
      } else {
        Ok(number.to_string())
      }
    (AttributeStringType, AttributeText(text)) => {
      let escaped = match escape_dbc_comment(text) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
      Ok("\"\{escaped}\"")
    }
    (AttributeEnumType(choices), AttributeInteger(index)) =>
      if index >= 0 && index < choices.length().to_int64() {
        Ok(index.to_string())
      } else {
        Err(DbcWriteInvalidAttribute("enumeration index is invalid"))
      }
    (AttributeEnumType(choices), AttributeText(text)) => {
      for choice in choices {
        if choice == text {
          let escaped = match escape_dbc_comment(text) {
            Ok(value) => value
            Err(error) => return Err(error)
          }
          return Ok("\"\{escaped}\"")
        }
      }
      Err(DbcWriteInvalidAttribute("enumeration value is undeclared"))
    }
    _ => Err(DbcWriteInvalidAttribute("value does not match its definition"))
  }
}

///|
fn attribute_target_text(target : DbcAttributeTarget) -> String {
  match target {
    DatabaseAttributeTarget => ""
    NodeAttributeTarget(node) => " BU_ \{node}"
    MessageAttributeTarget(id) => " BO_ \{id}"
    SignalAttributeTarget(id, signal) => " SG_ \{id} \{signal}"
  }
}

///|
fn write_attributes(
  lines : Array[String],
  attributes : DbcAttributes,
) -> Result[Unit, DbcWriteError] {
  for definition in attributes.definitions {
    if definition.name.is_empty() ||
      definition.name.view().contains("\"") ||
      definition.name.view().contains("\\") {
      return Err(DbcWriteInvalidAttribute("definition name is invalid"))
    }
    let name = match escape_dbc_comment(definition.name) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    let value_type = match attribute_type_text(definition.value_type) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    lines.push(
      "BA_DEF_ \{attribute_scope_text(definition.scope)}\"\{name}\" \{value_type};",
    )
  }
  if !attributes.definitions.is_empty() &&
    (!attributes.defaults.is_empty() || !attributes.assignments.is_empty()) {
    lines.push("")
  }
  for default in attributes.defaults {
    let definition = match
      find_attribute_definition(attributes.definitions, default.name) {
      Some(value) => value
      None => return Err(DbcWriteInvalidAttribute("default has no definition"))
    }
    let value = match
      attribute_value_text(default.value, definition.value_type) {
      Ok(text) => text
      Err(error) => return Err(error)
    }
    let name = match escape_dbc_comment(default.name) {
      Ok(text) => text
      Err(error) => return Err(error)
    }
    lines.push("BA_DEF_DEF_ \"\{name}\" \{value};")
  }
  if !attributes.defaults.is_empty() && !attributes.assignments.is_empty() {
    lines.push("")
  }
  for assignment in attributes.assignments {
    let definition = match
      find_attribute_definition(attributes.definitions, assignment.name) {
      Some(value) => value
      None =>
        return Err(DbcWriteInvalidAttribute("assignment has no definition"))
    }
    if definition.scope != attribute_target_scope(assignment.target) {
      return Err(DbcWriteInvalidAttribute("assignment scope does not match"))
    }
    match assignment.target {
      NodeAttributeTarget(node) =>
        match check_dbc_token("attribute node", node) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      SignalAttributeTarget(_, signal) =>
        match check_dbc_token("attribute signal", signal) {
          Err(error) => return Err(error)
          Ok(_) => ()
        }
      _ => ()
    }
    let value = match
      attribute_value_text(assignment.value, definition.value_type) {
      Ok(text) => text
      Err(error) => return Err(error)
    }
    let name = match escape_dbc_comment(assignment.name) {
      Ok(text) => text
      Err(error) => return Err(error)
    }
    lines.push(
      "BA_ \"\{name}\"\{attribute_target_text(assignment.target)} \{value};",
    )
  }
  Ok(())
}
