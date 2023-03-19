import 'dart:convert';
import 'dart:io';

import 'package:gql_tools/schema.dart';
import 'package:path/path.dart' as path;

void main(List<String> args) async {
  final schema = await GraphqlSchema.fromUrl("http://localhost:5000/graphql");

  final jsonSchema = schema.convertToJson();
  final schemaJsonFile = File(path.join(path.dirname(Platform.script.path), 'schema.g.json'));
  await schemaJsonFile.writeAsString(json.encoder.convert(jsonSchema));

  final sdlSchema = schema.convertToSdl();
  final schemaSdlFile = File(path.join(path.dirname(Platform.script.path), 'schema.g.graphql'));
  await schemaSdlFile.writeAsString(sdlSchema);

  final dartModels = schema.generateDartModels({"MongoID": "String", "Upload": "String"});
  final dartModelFile = File(path.join(path.dirname(Platform.script.path), 'models.g.dart'));
  await dartModelFile.writeAsString(dartModels);
}
