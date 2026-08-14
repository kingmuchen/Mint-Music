import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/models/song.dart';

final mockSongsProvider = Provider<List<Song>>((ref) {
  return [
    const Song(
      id: '1',
      title: '晴天',
      artist: '周杰伦',
      album: '叶惠美',
      duration: 269,
    ),
    const Song(
      id: '2',
      title: '成都',
      artist: '赵雷',
      album: '无法长大',
      duration: 336,
    ),
    const Song(
      id: '3',
      title: 'Despacito',
      artist: 'Luis Fonsi',
      album: 'Vida',
      duration: 228,
    ),
    const Song(
      id: '4',
      title: '山海',
      artist: '草东没有派对',
      album: '丑奴儿',
      duration: 246,
    ),
    const Song(
      id: '5',
      title: '平凡之路',
      artist: '朴树',
      album: '猎户星座',
      duration: 294,
    ),
    const Song(
      id: '6',
      title: '稻香',
      artist: '周杰伦',
      album: '魔杰座',
      duration: 223,
    ),
    const Song(
      id: '7',
      title: 'See You Again',
      artist: 'Wiz Khalifa',
      album: 'Furious 7',
      duration: 230,
    ),
    const Song(
      id: '8',
      title: '那些花儿',
      artist: '朴树',
      album: '我去2000年',
      duration: 243,
    ),
    const Song(
      id: '9',
      title: '夜空中最亮的星',
      artist: '逃跑计划',
      album: '世界',
      duration: 258,
    ),
    const Song(
      id: '10',
      title: '年少有为',
      artist: '李荣浩',
      album: '耳朵',
      duration: 304,
    ),
  ];
});
