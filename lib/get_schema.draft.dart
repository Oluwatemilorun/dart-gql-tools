import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

String query = """
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

Map<String, dynamic> queryBody = {
  "operationName": 'IntrospectionQuery',
  "variables": {},
  "query": query,
};

Future<Stream> getSchemaStream() async {
  final client = HttpClient();
  final uri = Uri.parse("http://localhost:5000/graphql");
  final body = json.encode(queryBody);
  final httpRequest = await client.postUrl(uri);
  httpRequest.headers.add(HttpHeaders.contentTypeHeader, "application/json");
  httpRequest.write(body);
  final httpResponse = await httpRequest.close();
  return httpResponse.transform(utf8.decoder);
}

Future<Map<String, dynamic>> schemaStreamToJson(Stream stream) async {
  const JsonDecoder decoder = JsonDecoder();
  final json = await stream.transform(decoder).first;
  return json as Map<String, dynamic>;
}

printSchema(Map<String, dynamic> json) {
  final buffer = StringBuffer();

  // Iterate over the types in the schema
  for (final typeEntry in json['data']['__schema']['types']) {
    final type = typeEntry['name'];

    // Ignore introspection types
    if (type.startsWith('__')) continue;

    // Output the type definition
    buffer.writeln('type $type {');

    // Output the fields in the type
    for (final field in typeEntry['fields']) {
      buffer.write('  ${field['name']}: ${_getType(field['type'])}');
      if (field['isDeprecated']) {
        buffer.write(' @deprecated');
      }
      buffer.writeln();
    }

    buffer.writeln('}');
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

void main(List<String> args) async {
  const JsonDecoder decoder = JsonDecoder();

  final stream = await getSchemaStream();
  final jsonSchema = await stream.join();
  final sdlSchema = printSchema(decoder.convert(jsonSchema));

  final schemaJsonFile = File(path.join(path.dirname(Platform.script.path), 'schema.json'));
  final schemaSdlFile = File(path.join(path.dirname(Platform.script.path), 'schema.graphql'));
  await schemaJsonFile.writeAsString(jsonSchema);
  await schemaSdlFile.writeAsString(sdlSchema);
}
