class UserProfile {
  final String uid;
  final String nome;
  final String matricula;
  final String empresa;
  final String? photoUrl;

  UserProfile({
    required this.uid,
    required this.nome,
    required this.matricula,
    required this.empresa,
    this.photoUrl,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'nome': nome,
      'matricula': matricula,
      'empresa': empresa,
      if (photoUrl != null) 'photoUrl': photoUrl,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      uid: map['uid'] as String? ?? '',
      nome: map['nome'] as String? ?? '',
      matricula: map['matricula'] as String? ?? '',
      empresa: map['empresa'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
    );
  }
}

