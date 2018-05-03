# Статистика по комментариям в сообществах

tarantool> box.space.comments.index.wall:pairs():grep(function(t) return t[F.comments.text] ~= nil end):grep(function(t) return t[F.comments.wall] < 0 end):map(function(t) return t[F.comments.wall] end):foldl(function(acc, t) acc[t]=(acc[t] or 0) + 1 return acc end, {})
---
- -29166271: 544
  -126991295: 851
  -740718: 9243
  -89940003: 15
  -73046961: 365
  -10933209: 24817
  -31191269: 1816
  -46884472: 9
  -30666517: 1794
  -32419913: 40
  -78929175: 759
  -107068423: 1407
  -54295855: 22045
  -57846937: 32544
  -73268685: 1
...


