import 'dart:convert';
import 'dart:io';

class GraphqlSchema {
  final GraphqlSchemaFormat format;
  final String schemaStream;
  final JsonDecoder decoder = JsonDecoder();

  GraphqlSchema(this.format, this.schemaStream);

  static Future<GraphqlSchema> fromUrl(String url) async {
    final stream = await getSchemaStream(url);
    final jsonSchema = await stream.join();
    return GraphqlSchema(GraphqlSchemaFormat.JSON, jsonSchema);
  }

  String convertToSdl() {
    if (format == GraphqlSchemaFormat.SDL) {
      return schemaStream;
    }

    return jsonToSdlSchema(decoder.convert(schemaStream));
  }

  Map<String, dynamic> convertToJson() {
    if (format == GraphqlSchemaFormat.JSON) {
      return decoder.convert(schemaStream);
    }

    return {}; // TODO: write code to convert sdl to json
  }

  String generateDartModels(Map<String, String> customTypes) {
    final json = convertToJson();
    return jsonToDartClass(json, customTypes);
  }

  // TODO: write code to generate queries for each of the available queries
  // TODO: write code generate an HTTP client package that utilizes the generated queries
}

/// The GraphQL schema format types
enum GraphqlSchemaFormat {
  SDL,
  JSON,
}

Future<Stream> getSchemaStream(String url) async {
  final client = HttpClient();
  final uri = Uri.parse(url);
  final body = json.encode(_queryBody);

  final httpRequest = await client.postUrl(uri);

  httpRequest.headers.add(HttpHeaders.contentTypeHeader, "application/json");
  httpRequest.write(body);

  final httpResponse = await httpRequest.close();
  return httpResponse.transform(utf8.decoder);
}

String jsonToSdlSchema(Map<String, dynamic> json) {
  final buffer = StringBuffer();

  // Iterate over the types in the schema
  for (final typeEntry in json['data']['__schema']['types']) {
    final type = typeEntry['name'];

    // Ignore introspection types
    if (type.startsWith('__')) continue;

    // Output the type definition
    switch (typeEntry['kind']) {
      case 'SCALAR':
        buffer.writeln('scalar $type');
        break;
      case 'OBJECT':
        buffer.write('type $type');
        // Check if the object type implements any interfaces
        if (typeEntry['interfaces'].isNotEmpty) {
          final interfaces = typeEntry['interfaces'].map((i) => i['name']).join(' & ');
          buffer.write(' implements $interfaces');
        }
        buffer.writeln(' {');
        for (final field in typeEntry['fields']) {
          buffer.write(
              '  ${field['name']}${_objectTypeFieldArguments(field)}: ${_getType(field['type'])}');
          if (field['isDeprecated']) {
            buffer.write(' @deprecated');
          }
          buffer.writeln();
        }
        buffer.writeln('}');
        break;

      case 'INPUT_OBJECT':
        buffer.writeln('input $type {');
        for (final field in typeEntry['inputFields']) {
          buffer.write(
              '  ${field['name']}${_inputTypeFieldArguments(field)}: ${_getType(field['type'])}');
          buffer.writeln();
        }
        buffer.writeln('}');
        break;

      case 'ENUM':
        buffer.writeln('enum $type {');
        for (final enumValue in typeEntry['enumValues']) {
          buffer.writeln('  ${enumValue['name']}${_enumValueDirective(enumValue)}');
        }
        buffer.writeln('}');
        break;
    }
    buffer.writeln();
  }

  return buffer.toString();
}

String jsonToDartClass(Map<String, dynamic> json, Map<String, String> customTypes) {
  final buffer = StringBuffer();

  final queryType = json['data']['__schema']['queryType']['name'];
  final mutationType = json['data']['__schema']['mutationType']['name'];

  // Iterate over the types in the schema
  for (final typeEntry in json['data']['__schema']['types']) {
    String typeName = "${typeEntry['name']}";

    // Ignore introspection types
    if (typeName.startsWith('__')) continue;

    // handle query types
    if (typeName == queryType) {
      continue;
    }

    // handle mutation types
    if (typeName == mutationType) {
      continue;
    }

    // capitalize class names
    // typeName = _capitalize(typeName);

    // Output the class definition
    switch (typeEntry['kind']) {
      case 'OBJECT':
        buffer.writeln('class $typeName {');
        for (final field in typeEntry['fields']) {
          buffer.writeln('  ${_getFieldDeclaration(field, customTypes)}');
        }
        buffer.writeln();
        buffer.writeln('  $typeName({');
        for (final field in typeEntry['fields']) {
          buffer.writeln('    ${_getClassParamDeclaration(field)},');
        }
        buffer.writeln('  });');
        buffer.writeln();
        buffer.writeln('  factory $typeName.fromJson(Map<String, dynamic> json) {');
        buffer.writeln('    return $typeName(');
        for (final field in typeEntry['fields']) {
          buffer.writeln('      ${_getFromJsonFieldDeclaration(field, customTypes)},');
        }
        buffer.writeln('    );');
        buffer.writeln('  }');
        buffer.writeln('}');
        break;

      case 'INPUT_OBJECT':
        buffer.writeln('class $typeName {');
        for (final field in typeEntry['inputFields']) {
          buffer.writeln('  ${_getFieldDeclaration(field, customTypes)}');
        }
        buffer.writeln();
        buffer.writeln('  $typeName({');
        for (final field in typeEntry['inputFields']) {
          buffer.writeln('    ${_getClassParamDeclaration(field)},');
        }
        buffer.writeln('  });');
        buffer.writeln();
        buffer.writeln('  Map<String, dynamic> toJson() {');
        buffer.writeln('    final Map<String, dynamic> data = {};');
        for (final field in typeEntry['inputFields']) {
          buffer.writeln('    ${_getToJsonFieldDeclaration(field)}');
        }
        buffer.writeln('    return data;');
        buffer.writeln('  }');
        buffer.writeln('}');
        break;

      case 'ENUM':
        buffer.writeln('enum $typeName {');
        for (final enumValue in typeEntry['enumValues']) {
          final enumName = enumValue['name'];
          buffer.writeln('  $enumName,');
        }
        buffer.writeln('}');
        break;
    }
    buffer.writeln();
  }

  return buffer.toString();
}

/// recursively converts a GraphQL type object from JSON format to GraphQL schema language.
String _getType(dynamic type) {
  if (type['kind'] == 'NON_NULL') {
    return '${_getType(type['ofType'])}!';
  } else if (type['kind'] == 'LIST') {
    return '[${_getType(type['ofType'])}]';
  } else {
    return type['name'];
  }
}

String _enumValueDirective(dynamic enumValue) {
  final deprecationReason = enumValue['deprecationReason'];
  if (deprecationReason != null) {
    return ' @deprecated(reason: "$deprecationReason")';
  } else {
    return '';
  }
}

String _objectTypeFieldArguments(dynamic field) {
  if (field['args'] == null || field['args'].isEmpty) {
    return '';
  } else {
    final args = field['args']
        .map((arg) => '${arg['name']}: ${_getType(arg['type'])}${_fieldArgumentDefaultValue(arg)}')
        .join(', ');
    return '($args)';
  }
}

String _inputTypeFieldArguments(dynamic field) {
  if (field['inputFields'] == null || field['inputFields'].isEmpty) {
    return '';
  } else {
    final args = field['inputFields']
        .map((inputField) =>
            '${inputField['name']}: ${_getType(inputField['type'])}${_fieldArgumentDefaultValue(inputField)}')
        .join(', ');
    return '($args)';
  }
}

String _fieldArgumentDefaultValue(dynamic arg) {
  if (arg['defaultValue'] != null) {
    return ' = ${arg['defaultValue']}';
  } else {
    return '';
  }
}

String _getDartType(dynamic type, Map<String, String> customTypes) {
  if (type['kind'] == 'NON_NULL') {
    return _getDartType(type['ofType'], customTypes);
  } else if (type['kind'] == 'LIST') {
    return 'List<${_getDartType(type['ofType'], customTypes)}>';
  } else if (customTypes.containsKey(type['name'])) {
    return customTypes[type['name']]!;
  } else {
    switch (type['name']) {
      case 'String':
      case 'ID':
      case 'UUID':
        return 'String';
      case 'Int':
        return 'int';
      case 'Float':
        return 'double';
      case 'Boolean':
        return 'bool';
      case 'JSON':
        return 'Map<String, dynamic>';
      default:
        return 'dynamic';
    }
  }
}

String _getFieldDeclaration(Map<String, dynamic> field, Map<String, String> customTypes) {
  final name = _getSafeFieldName(field['name']);
  final type = _getDartType(field['type'], customTypes);
  final isNullable = _isNullable(field['type']);

  return 'final $type${isNullable && type != 'dynamic' ? '?' : ''} $name;';
}

String _getClassParamDeclaration(Map<String, dynamic> field) {
  final name = _getSafeFieldName(field['name']);
  final isNullable = _isNullable(field['type']);

  return '${isNullable ? '' : 'required '}this.$name';
}

String _getFromJsonFieldDeclaration(Map<String, dynamic> field, Map<String, String> customTypes) {
  final name = _getSafeFieldName(field['name']);
  final type = _getDartType(field['type'], customTypes);
  final isNullable = _isNullable(field['type']);

  return '$name: json["${field['name']}"] as $type${isNullable && type != 'dynamic' ? '?' : ''}';
}

String _getToJsonFieldDeclaration(Map<String, dynamic> field) {
  final name = _getSafeFieldName(field['name']);

  return ' data["${field['name']}"] = $name;';
}

bool _isNullable(dynamic type) {
  if (type['kind'] == 'NON_NULL') {
    return false;
  } else {
    return true;
  }
}

String _capitalize(String s) {
  return s.substring(0, 1).toUpperCase() + s.substring(1);
}

String _getSafeFieldName(String name) {
  // List of illegal variable names in Dart
  const illegalNames = [
    'abstract',
    'as',
    'assert',
    'async',
    'await',
    'break',
    'case',
    'catch',
    'class',
    'const',
    'continue',
    'covariant',
    'default',
    'deferred',
    'do',
    'dynamic',
    'else',
    'enum',
    'export',
    'extends',
    'extension',
    'external',
    'factory',
    'false',
    'final',
    'finally',
    'for',
    'Function',
    'get',
    'hide',
    'if',
    'implements',
    'import',
    'in',
    'inout',
    'interface',
    'is',
    'late',
    'library',
    'mixin',
    'native',
    'new',
    'null',
    'of',
    'on',
    'operator',
    'out',
    'part',
    'patch',
    'required',
    'rethrow',
    'return',
    'set',
    'show',
    'source',
    'static',
    'super',
    'switch',
    'sync',
    'this',
    'throw',
    'true',
    'try',
    'typedef',
    'var',
    'void',
    'while',
    'with',
    'yield',
  ];

  // Check if name is illegal
  if (illegalNames.contains(name)) {
    name = '\$$name';
  }

  if (name.startsWith("_")) {
    name = name.substring(1);
  }

  return name;
}

String _query = """
query IntrospectionQuery {
  __schema {
    queryType {
      name
    }
    mutationType {
      name
    }
    subscriptionType {
      name
    }
    types {
      ...FullType
    }
    directives {
      name
      description
      locations
      args {
        ...InputValue
      }
    }
  }
}

fragment FullType on __Type {
  kind
  name
  description
  fields(includeDeprecated: true) {
    name
    description
    args {
      ...InputValue
    }
    type {
      ...TypeRef
    }
    isDeprecated
    deprecationReason
  }
  inputFields {
    ...InputValue
  }
  interfaces {
    ...TypeRef
  }
  enumValues(includeDeprecated: true) {
    name
    description
    isDeprecated
    deprecationReason
  }
  possibleTypes {
    ...TypeRef
  }
}

fragment InputValue on __InputValue {
  name
  description
  type {
    ...TypeRef
  }
  defaultValue
}

fragment TypeRef on __Type {
  kind
  name
  ofType {
    kind
    name
    ofType {
      kind
      name
      ofType {
        kind
        name
        ofType {
          kind
          name
          ofType {
            kind
            name
            ofType {
              kind
              name
              ofType {
                kind
                name
              }
            }
          }
        }
      }
    }
  }
}
""";

Map<String, dynamic> _queryBody = {
  "operationName": 'IntrospectionQuery',
  "variables": {},
  "query": _query,
};
