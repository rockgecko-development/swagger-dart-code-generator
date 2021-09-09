import 'package:swagger_dart_code_generator/src/definitions.dart';
import 'package:recase/recase.dart';
import 'package:swagger_dart_code_generator/src/extensions/file_name_extensions.dart';
import 'package:swagger_dart_code_generator/src/models/generator_options.dart';

///Generates index file content, converter and additional methods
class SwaggerAdditionsGenerator {
  static const mappingVariableName = 'generatedMapping';

  ///Generates index.dart for all generated services
  String generateIndexes(Map<String, List<String>> buildExtensions) {
    final importsList = buildExtensions.keys.map((String key) {
      final fileName = key
          .split('/')
          .last
          .replaceAll('-', '_')
          .replaceAll('.json', '.swagger');
      final className = getClassNameFromFileName(key.split('/').last);

      return 'export \'$fileName.dart\' show $className;';
    }).toList();

    importsList.sort();

    return importsList.join('\n');
  }

  ///Generated Map of all models generated by generator
  String generateConverterMappings(
      Map<String, List<String>> buildExtensions, bool hasModels) {
    if (!hasModels) {
      return '';
    }

    final maps = StringBuffer();
    final imports = <String>[];
    buildExtensions.keys.forEach((String key) {
      final className =
          "${getClassNameFromFileName(key.split('/').last)}$converterClassEnding";

      final fileName = getFileNameBase(key);
      maps.writeln('  ...$className,');
      imports.add("import '$fileName.swagger.dart';");
    });

    imports.sort();

    final mapping = '''
${imports.join('\n')}

final Map<Type, Object Function(Map<String, dynamic>)> $mappingVariableName = {
$maps};
''';

    return mapping;
  }

  ///Generated imports for concrete service
  String generateImportsContent(String swaggerFileName, bool hasModels,
      bool buildOnlyModels, bool hasEnums) {
    final result = StringBuffer();

    final chopperPartImport =
        buildOnlyModels ? '' : "part '$swaggerFileName.swagger.chopper.dart';";

    final chopperImports = buildOnlyModels
        ? ''
        : '''import 'package:chopper/chopper.dart';
import 'package:chopper/chopper.dart' as chopper;''';

    final enumsImport = hasEnums
        ? "import '$swaggerFileName.enums.swagger.dart' as enums;"
        : '';

    final enumsExport =
        hasEnums ? "export '$swaggerFileName.enums.swagger.dart';" : '';

    if (hasModels) {
      result.writeln("""
import 'package:json_annotation/json_annotation.dart';
import 'package:collection/collection.dart';
""");
    }

    if (chopperImports.isNotEmpty) {
      result.write(chopperImports);
    }
    if (enumsImport.isNotEmpty) {
      result.write(enumsImport);
    }

    if (enumsExport.isNotEmpty) {
      result.write(enumsExport);
    }

    result.write('\n\n');

    if (chopperPartImport.isNotEmpty) {
      result.write(chopperPartImport);
    }
    if (hasModels) {
      result.write("part '$swaggerFileName.swagger.g.dart';");
    }

    return result.toString();
  }

  ///Additional method to convert date to json
  String generateDateToJson() {
    return '''
// ignore: unused_element
String? _dateToJson(DateTime? date) {
  if(date == null)
  {
    return null;
  }
  
  final year = date.year.toString();
  final month = date.month < 10 ? '0\${date.month}' : date.month.toString();
  final day = date.day < 10 ? '0\${date.day}' : date.day.toString();

  return '\$year-\$month-\$day';
  }
''';
  }

  ///Copy-pasted converter from internet
  String generateCustomJsonConverter(
      String fileName, GeneratorOptions options) {
    if (!options.withConverter) {
      return '';
    }
    return '''
typedef \$JsonFactory<T> = T Function(Map<String, dynamic> json);

class \$CustomJsonDecoder {
  \$CustomJsonDecoder(this.factories);

  final Map<Type, \$JsonFactory> factories;

  dynamic decode<T>(dynamic entity) {
    if (entity is Iterable) {
      return _decodeList<T>(entity);
    }

    if (entity is T) {
      return entity;
    }

    if (entity is Map<String, dynamic>) {
      return _decodeMap<T>(entity);
    }

    return entity;
  }

  T _decodeMap<T>(Map<String, dynamic> values) {
    final jsonFactory = factories[T];
    if (jsonFactory == null || jsonFactory is! \$JsonFactory<T>) {
      return throw "Could not find factory for type \$T. Is '\$T: \$T.fromJsonFactory' included in the CustomJsonDecoder instance creation in bootstrapper.dart?";
    }

    return jsonFactory(values);
  }

  List<T> _decodeList<T>(Iterable values) =>
      values.where((dynamic v) => v != null).map<T>((dynamic v) => decode<T>(v) as T).toList();
}

class \$JsonSerializableConverter extends chopper.JsonConverter {
  @override
  chopper.Response<ResultType> convertResponse<ResultType, Item>(chopper.Response response) {
    if (response.bodyString.isEmpty) {
      // In rare cases, when let's say 204 (no content) is returned -
      // we cannot decode the missing json with the result type specified
      return chopper.Response(response.base, null, error: response.error);
    }

    final jsonRes = super.convertResponse<ResultType, Item>(response);
    return jsonRes.copyWith<ResultType>(
        body: \$jsonDecoder.decode<Item>(jsonRes.body) as ResultType);
  }
}

final \$jsonDecoder = \$CustomJsonDecoder(${fileName.pascalCase}JsonDecoderMappings);
    ''';
  }

  static String getChopperClientContent(
    String className,
    String host,
    String basePath,
    GeneratorOptions options,
  ) {
    final baseUrlString = options.withBaseUrl
        ? "baseUrl:  'https://$host$basePath'"
        : '/*baseUrl: YOUR_BASE_URL*/';

    final converterString = options.withConverter
        ? 'converter: \$JsonSerializableConverter(),'
        : 'converter: chopper.JsonConverter(),';

    final chopperClientBody = '''
    if(client!=null){
      return _\$$className(client);
    }

    final newClient = ChopperClient(
      services: [_\$$className()],
      $converterString
      $baseUrlString);
    return _\$$className(newClient);
''';
    return chopperClientBody;
  }
}
