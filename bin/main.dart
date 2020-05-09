import 'package:angel_framework/angel_framework.dart';
import 'package:postgres/postgres.dart';
import 'package:angel_hot/angel_hot.dart';
import 'package:logging/logging.dart';
import 'dart:async';
import 'package:file/local.dart';

main() async {
  var hot = HotReloader(createServer, ["bin"]);
  await hot.startServer("192.168.1.100", 8383);
}

Future<Angel> createServer() async {
  var app = Angel();
  //var http = AngelHttp(app);
  var fs = const LocalFileSystem();
  app.logger = new Logger('API Server')
    ..onRecord.listen((rec) {
      print(rec.toString());
      if (rec.error != null) print(rec.error);
      if (rec.stackTrace != null) print(rec.stackTrace);
    });

  app.mimeTypeResolver.addExtension('yaml', 'text/yaml');
  app.get("/", (req, res) {
    return res.streamFile(fs.file('pubspec.yaml'));
  });

////////////////////
  // LOGIN
  login(_username, _password) async {
    final connection = PostgreSQLConnection(
      "192.168.1.100",
      5432,
      "miniproj",
      username: "postgres",
      password: "12345678",
    );
    try {
      await connection.open();
      var result = await connection.query(
        "SELECT * FROM t_accounts WHERE (username = @username OR email = @username) AND password = @password",
        substitutionValues: {"username": _username, "password": _password},
      );

      return (result.length > 0) ? [0, result[0][0]] : [1, null];
    } on PostgreSQLException catch (err) {
      print('PostgreSQLException: $err');
      return [2, null];
    } catch (err) {
      print(err);
      return [2, null];
    } finally {
      connection.close();
    }
  }

  app.post('/login', (req, res) async {
    await req.parseBody();

    bool valid;
    int userID;
    String _username = req.bodyAsMap['username'];
    String _password = req.bodyAsMap['password'];
    final result = await login(_username, _password);
    if (result[0] == 0) {
      valid = true;
      userID = result[1];
    } else if (result[0] == 1) {
      valid = false;
      userID = null;
    } else if (result[0] == 2) {
      valid = null;
      userID = null;
    }

    res.json({'authenticate': valid, 'userID': userID});
    return res;
  });
  // LOGIN
//////////////////////////

  search(int userID, {String username, String location, int category}) async {
    if (username != null) {
      location = null;
      category = null;
    } else {
      username = '';
    }
    final connection = PostgreSQLConnection(
      "192.168.1.100",
      5432,
      "miniproj",
      username: "postgres",
      password: "12345678",
    );
    try {
      await connection.open();
      print('Searching...');
      final result = await connection.query(
        '''
      SELECT 
        DISTINCT t_accounts.user_id,
        t_accounts.username,
        t_userdata.first_name,
        t_userdata.avatar,
        t_userdata.contact,
        t_location.location_name,
        t_userdata.description
		FROM t_accounts
      LEFT JOIN t_userdata ON t_accounts.user_id = t_userdata.user_id
      LEFT JOIN t_location ON t_accounts.user_id = t_location.user_id
	  LEFT JOIN t_user_category ON t_accounts.user_id = t_user_category.user_id
	  WHERE (t_user_category.category_id = (CASE WHEN @category::integer IS NOT NULL THEN @category::integer ELSE category_id END))
	  AND (t_location.location_name = (CASE WHEN @location::text IS NOT NULL THEN @location::text ELSE location_name END))
	  AND (t_accounts.username LIKE (CASE WHEN @username::text IS NOT NULL THEN @username::text ELSE username END) or t_userdata.first_name LIKE (CASE WHEN @username::text IS NOT NULL THEN @username::text ELSE first_name END))
    AND t_accounts.user_id != @userID;
    ''',
        substitutionValues: {
          "userID": userID,
          "username": '%' + username + '%',
          "location": location,
          "category": category
        },
      );

      return result;
    } on PostgreSQLException catch (err) {
      print('PostgreSQLException: $err');
      return [];
    } finally {
      await connection.close();
    }
  }

  app.post('/search', (req, res) async {
    await req.parseBody();
    int userID = req.bodyAsMap['myUserID'];
    String username = req.bodyAsMap['username'];
    String location = req.bodyAsMap['location'];
    int category = req.bodyAsMap['category'];
    final List results = await search(userID,
        username: username, location: location, category: category);
    var jsonresult = [];
    results.forEach((row) => {
          jsonresult.add({
            'userID': row[0],
            'username': row[1],
            'first_name': row[2],
            'avatar': row[3],
            'contact': row[4],
            'location': row[5],
            'description': row[6]
          })
        });
    res.json(jsonresult);
    return res;
  });

  getUserData(_userID) async {
    final connection = PostgreSQLConnection(
      "192.168.1.100",
      5432,
      "miniproj",
      username: "postgres",
      password: "12345678",
    );
    try {
      print('Getting UserData in...');
      await connection.open();
      final result = await connection.mappedResultsQuery(
        '''
      SELECT 
        t_accounts.user_id,
        t_accounts.username,
        t_accounts.email,
        t_userdata.first_name,
        t_userdata.last_name,
        t_userdata.avatar,
        t_userdata.contact,
        t_location.location_name,
        t_userdata.description
        
      FROM t_accounts
      LEFT JOIN t_userdata ON t_accounts.user_id = t_userdata.user_id
      LEFT Join t_location ON t_accounts.user_id = t_location.user_id
      WHERE t_accounts.user_id = @user_id;
    ''',
        substitutionValues: {"user_id": _userID},
      );
      final userData = {};
      result[0].values.forEach((v) => userData.addAll(v));
      print(userData);
      return userData;
    } on PostgreSQLException catch (err) {
      print('PostgreSQLException: $err');
      return {};
    } finally {
      await connection.close();
    }
  }

  app.get('profile/int:id', (req, res) async {
    var id = req.params['id'] as int;
    final userdata = await getUserData(id);
    
    res.json(userdata);
    return res;
  });

  return app;
}
