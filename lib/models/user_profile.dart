class UserProfile {
  final String uid;
  final String nome;
  final String matricula;
  final String empresa;
  final String? photoUrl;
  final String driverId;
  final String? name;
  final String? nickname;

  UserProfile({
    required this.uid,
    required this.nome,
    required this.matricula,
    required this.empresa,
    this.photoUrl,
    this.driverId = '',
    this.name,
    this.nickname,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nome': nome,
      'matricula': matricula,
      'empresa': empresa,
      'driverId': driverId,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (name != null) 'name': name,
      if (nickname != null) 'nickname': nickname,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      matricula: map['matricula'] as String? ?? '',
      empresa: map['empresa'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      driverId: map['driverId'] as String? ?? '',
      name: map['name'] as String?,
      nickname: map['nickname'] as String?,
    );
  }
}

