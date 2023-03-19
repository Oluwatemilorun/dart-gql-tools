# Dart GrahpQL Tools

**A simple package to help with code generation with GraphQl.**

At the moment, there is `GraphqlSchema` class that has the ability to
- Generate a graphql schema from a given URL
```dart
main() async {
  // Get the graphql schema from a url
  final schema = await GraphqlSchema.fromUrl("http://localhost:5000/graphql");

  // Generate a graphql schema in json format.
  // You can write the output string into a JSON file (schema.json)
  final jsonSchema = schema.convertToJson();

  // Generate a graphql schema in SDL format.
  // You can write the output string into a .graphql or .gql file (schema.graphql)
  final sdlSchema = schema.convertToSdl();

  // Generate dart class models from the Graphql types
  // It accepts an arguement that allows you map custom graphql scalar types to a dart type
  final dartModels = schema.generateDartModels({"MongoID": "String", "Upload": "String"});
}
```
