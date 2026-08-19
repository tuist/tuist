/*
 * Dither globe (cache "Low latency, everywhere" card): a slowly spinning
 * stippled sphere — lat/long wireframe, Natural Earth coastlines, land
 * fill and ocean grain — rendered through the marketing dither texture:
 * every dot snaps to the 2px cell grid as a full 2px square, colored from
 * the shallow → mid → deep token ramp (interleaved per cell with a stable
 * hash so the shades scatter instead of banding), and the spin advances at
 * full rAF rate so the rotation stays smooth at chunky pitches. Dragging
 * the canvas rotates the globe (trackball); under prefers-reduced-motion
 * the globe holds a static frame.
 *
 * Options (all data attributes):
 *   data-size:      globe radius as a fraction of min(w, h) / 2
 *   data-pitch:     dither cell/dot size in px (the texture's grain)
 *   data-tilt-x:    forward tilt in radians
 *   data-tilt-z:    sideways tilt in radians
 *   data-speed:     spin in rad/s around the globe's own pole
 *   data-meridians: meridian great circles
 *   data-parallels: parallel rings
 *   data-density:   0-100 — arc spacing of the wireframe/coastline dots
 *   data-shade:     0-100 — terminator shading stipple amount
 *   data-land:      0-100 — land fill stipple amount
 *   data-ocean:     0-100 — ocean grain stipple amount
 *   data-offset-x / data-offset-y: center offset in px
 */

import { onThemeChange } from "../lib/theme.js";


// Deterministic hash in [0, 1): stable per cell, so the shade interleave
// never reshuffles between frames.
function noise2(x, y) {
  let h = (Math.imul(x + 1, 374761393) + Math.imul(y + 1, 668265263)) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

function resolveTokenColor(host, name) {
  const probe = document.createElement("span");
  probe.style.position = "absolute";
  probe.style.visibility = "hidden";
  probe.style.color = `var(${name})`;
  host.appendChild(probe);
  const resolved = getComputedStyle(probe).color;
  probe.remove();
  const c = document.createElement("canvas");
  c.width = c.height = 1;
  const ctx = c.getContext("2d");
  ctx.fillStyle = resolved;
  ctx.fillRect(0, 0, 1, 1);
  const [r, g, b] = ctx.getImageData(0, 0, 1, 1).data;
  return [r, g, b];
}

/* ---------- 3x3 rotation helpers --------------------------------- */
function matMul(a, b) {
  const o = new Array(9);
  for (let r = 0; r < 3; r++) {
    for (let c = 0; c < 3; c++) {
      o[r * 3 + c] = a[r * 3] * b[c] + a[r * 3 + 1] * b[3 + c] + a[r * 3 + 2] * b[6 + c];
    }
  }
  return o;
}

function rotAxis(ax, ay, az, ang) {
  const l = Math.hypot(ax, ay, az) || 1;
  ax /= l;
  ay /= l;
  az /= l;
  const c = Math.cos(ang);
  const s = Math.sin(ang);
  const t = 1 - c;
  return [
    t * ax * ax + c,
    t * ax * ay - s * az,
    t * ax * az + s * ay,
    t * ax * ay + s * az,
    t * ay * ay + c,
    t * ay * az - s * ax,
    t * ax * az - s * ay,
    t * ay * az + s * ax,
    t * az * az + c,
  ];
}

const IDENTITY = [1, 0, 0, 0, 1, 0, 0, 0, 1];

/* ---------- lighting (view space, top-left-front) ----------------- */
const L = (() => {
  const v = [-0.45, 0.55, 0.72];
  const l = Math.hypot(...v);
  return v.map((x) => x / l);
})();

/* ---------- fixed stipple field on the sphere --------------------- */
const STIP_N = 22000;
const stip = new Float32Array(STIP_N * 4); // x, y, z, rand
(function () {
  const ga = Math.PI * (3 - Math.sqrt(5));
  let seed = 1234567;
  const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let i = 0; i < STIP_N; i++) {
    const y = 1 - ((i + 0.5) * 2) / STIP_N;
    const r = Math.sqrt(1 - y * y);
    const th = ga * i;
    stip[i * 4] = Math.cos(th) * r;
    stip[i * 4 + 1] = y;
    stip[i * 4 + 2] = Math.sin(th) * r;
    stip[i * 4 + 3] = rnd();
  }
})();

/* ---------- world map (Natural Earth 110m land, quantized x10) ---- */
const LAND = [[-596,-800,-602,-810,-645,-809,-663,-803,-619,-804,-606,-796,-596,-800],[-1592,-795,-1611,-796,-1637,-786,-1612,-784,-1592,-795],[-452,-780,-439,-785,-433,-800,-505,-810,-542,-806,-510,-796,-487,-780,-452,-780],[-1212,-735,-1187,-735,-1202,-741,-1226,-737,-1212,-735],[-1256,-735,-1240,-739,-1273,-735,-1256,-735],[-990,-719,-968,-720,-962,-725,-1008,-725,-1023,-719,-990,-719],[-685,-710,-688,-722,-711,-725,-724,-725,-719,-721,-742,-724,-750,-717,-721,-712,-717,-695,-703,-689,-685,-710],[-586,-642,-620,-648,-626,-655,-621,-662,-637,-665,-657,-680,-632,-692,-618,-707,-608,-737,-644,-753,-706,-766,-772,-767,-737,-779,-779,-784,-780,-792,-754,-803,-597,-824,-582,-832,-498,-817,-428,-821,-408,-814,-285,-803,-297,-793,-356,-795,-358,-783,-289,-767,-175,-751,-157,-745,-154,-741,-165,-739,-154,-731,-123,-724,-103,-713,-74,-717,-69,-709,-43,-715,-7,-712,-2,-716,77,-699,95,-700,108,-708,134,-700,151,-704,193,-699,226,-707,271,-705,320,-697,339,-685,386,-698,545,-658,564,-660,587,-673,614,-680,641,-674,689,-679,697,-692,678,-703,691,-707,679,-719,699,-723,710,-721,739,-699,776,-695,791,-683,828,-672,868,-672,880,-662,897,-672,958,-674,997,-672,1028,-656,1062,-669,1136,-659,1156,-667,1198,-673,1232,-665,1288,-668,1348,-662,1351,-653,1375,-670,1455,-669,1466,-679,1488,-684,1525,-689,1543,-686,1616,-706,1673,-708,1712,-717,1693,-737,1661,-744,1636,-762,1635,-771,1647,-782,1670,-788,1618,-792,1598,-809,1694,-838,1800,-847,1800,-900,-1800,-900,-1800,-847,-1791,-841,-1744,-845,-1700,-839,-1581,-854,-1485,-856,-1431,-850,-1429,-846,-1536,-837,-1529,-820,-1568,-811,-1506,-813,-1464,-803,-1495,-794,-1553,-791,-1581,-780,-1584,-769,-1513,-774,-1461,-765,-1462,-754,-1352,-743,-1211,-745,-1139,-737,-1123,-747,-1113,-744,-1076,-752,-1006,-753,-1001,-749,-1025,-741,-1037,-726,-963,-736,-901,-733,-892,-726,-815,-739,-803,-731,-749,-739,-674,-725,-673,-716,-685,-697,-674,-681,-677,-673,-630,-646,-586,-634,-572,-635,-586,-642],[-677,-538,-650,-547,-655,-552,-670,-549,-681,-556,-692,-555,-723,-545,-747,-528,-711,-541,-693,-525,-686,-526,-677,-538],[-585,-511,-577,-515,-580,-519,-607,-523,-612,-518,-585,-511],[703,-497,687,-498,689,-486,705,-491,703,-497],[1454,-408,1483,-409,1479,-432,1460,-435,1447,-412,1447,-407,1454,-408],[1730,-409,1742,-413,1727,-434,1731,-439,1715,-442,1706,-459,1693,-466,1667,-462,1670,-451,1705,-430,1721,-410,1728,-405,1730,-409],[1746,-362,1753,-372,1754,-365,1768,-379,1785,-377,1780,-392,1772,-391,1760,-413,1752,-417,1747,-413,1752,-405,1749,-399,1738,-395,1746,-388,1747,-374,1726,-345,1743,-353,1746,-362],[1671,-222,1655,-217,1640,-201,1671,-222],[1784,-173,1786,-182,1774,-182,1777,-174,1784,-173],[1794,-168,1786,-166,1800,-161,1794,-168],[1671,-149,1673,-157,1668,-157,1666,-146,1671,-149],[501,-136,504,-157,497,-157,498,-169,471,-249,454,-256,440,-250,433,-221,444,-201,440,-174,444,-162,463,-158,477,-146,492,-120,501,-136],[1436,-138,1439,-145,1446,-142,1454,-150,1464,-190,1488,-204,1497,-223,1507,-224,1509,-235,1531,-261,1536,-281,1529,-316,1503,-357,1500,-374,1463,-390,1449,-384,1450,-379,1436,-388,1406,-380,1396,-361,1381,-356,1382,-344,1368,-353,1379,-336,1378,-329,1360,-349,1352,-345,1343,-326,1313,-315,1261,-322,1242,-330,1237,-339,1199,-340,1180,-351,1166,-350,1150,-342,1157,-333,1157,-316,1133,-261,1138,-265,1134,-256,1142,-263,1134,-244,1141,-218,1142,-225,1167,-207,1209,-197,1230,-164,1234,-173,1239,-171,1235,-166,1238,-161,1243,-163,1257,-142,1271,-138,1284,-149,1296,-150,1294,-144,1306,-125,1326,-121,1318,-113,1324,-111,1353,-122,1365,-119,1370,-124,1360,-133,1355,-150,1402,-177,1413,-164,1417,-124,1425,-107,1436,-138],[1621,-105,1624,-108,1617,-108,1613,-102,1621,-105],[1207,-102,1190,-96,1199,-94,1207,-102],[1609,-99,1598,-98,1597,-92,1609,-99],[1244,-101,1235,-102,1251,-87,1273,-84,1244,-101],[1179,-81,1191,-87,1167,-90,1179,-81],[1229,-81,1228,-86,1199,-88,1207,-82,1229,-81],[1086,-68,1105,-69,1108,-65,1157,-84,1146,-88,1054,-69,1061,-59,1086,-68],[1347,-62,1342,-69,1345,-54,1347,-62],[1559,-68,1552,-65,1545,-51,1559,-68],[1520,-55,1502,-63,1483,-57,1498,-55,1501,-50,1502,-55,1508,-55,1516,-48,1515,-42,1523,-43,1520,-55],[1272,-35,1269,-38,1260,-32,1272,-35],[1305,-31,1308,-39,1279,-34,1281,-28,1305,-31],[1531,-45,1528,-48,1524,-38,1507,-27,1522,-32,1531,-45],[1341,-12,1344,-28,1355,-34,1363,-23,1383,-17,1446,-39,1460,-55,1476,-61,1479,-66,1470,-67,1472,-74,1507,-106,1479,-101,1460,-81,1447,-76,1433,-82,1434,-90,1426,-93,1391,-81,1376,-84,1387,-73,1379,-54,1337,-35,1330,-41,1320,-28,1337,-22,1322,-22,1305,-9,1324,-4,1341,-12],[1252,14,1237,2,1202,2,1200,-5,1209,-14,1233,-6,1215,-19,1232,-53,1222,-53,1227,-45,1215,-46,1210,-26,1203,-29,1204,-55,1194,-54,1195,-35,1188,-28,1200,6,1209,13,1229,9,1252,14],[1287,11,1281,-9,1274,10,1279,22,1287,11],[1058,-59,1047,-59,1026,-42,986,18,953,55,975,52,1006,21,1017,21,1038,1,1034,-7,1061,-31,1058,-59],[1179,18,1190,9,1178,8,1175,-8,1166,-15,1161,-40,1160,-37,1149,-41,1133,-31,1121,-35,1117,-30,1102,-29,1101,-16,1091,-5,1091,13,1097,20,1112,19,1114,27,1130,31,1167,69,1192,54,1173,32,1179,18],[1264,84,1265,72,1262,63,1258,73,1254,68,1254,56,1242,62,1242,74,1236,78,1219,72,1235,87,1238,82,1255,90,1254,98,1262,93,1264,84],[812,62,803,60,799,68,801,98,818,75,812,62],[-609,101,-619,101,-611,109,-609,101],[1240,103,1230,90,1224,97,1229,109,1235,109,1233,103,1241,112,1240,103],[1185,93,1172,84,1195,114,1197,106,1185,93],[1219,119,1231,116,1220,104,1219,119],[1255,122,1258,110,1250,113,1253,104,1248,101,1243,115,1249,118,1243,126,1255,122],[1215,131,1213,122,1203,135,1215,131],[1213,185,1222,185,1225,171,1217,159,1217,143,1240,138,1241,125,1229,136,1227,132,1220,138,1206,139,1210,145,1201,150,1199,164,1203,160,1207,185,1213,185],[-656,182,-672,179,-672,184,-656,182],[-769,179,-783,182,-769,184,-762,179,-769,179],[-726,199,-700,196,-683,186,-687,182,-707,184,-714,176,-724,182,-745,183,-723,187,-734,196,-726,199],[1103,187,1095,182,1087,185,1086,194,1108,201,1103,187],[-1555,191,-1559,191,-1559,203,-1548,195,-1555,191],[-797,228,-742,203,-778,199,-771,204,-781,207,-787,216,-822,224,-818,226,-850,219,-823,232,-797,228],[-775,238,-784,246,-782,252,-775,238],[1212,228,1207,220,1201,236,1215,253,1220,250,1212,228],[-778,266,-789,264,-790,268,-778,266],[-770,266,-772,259,-778,270,-770,266],[1346,341,1342,332,1338,335,1330,327,1324,330,1329,341,1346,341],[346,357,330,346,323,351,346,357],[237,357,263,353,247,349,235,353,237,357],[155,382,151,366,124,376,126,381,155,382],[92,412,98,405,97,392,88,389,82,410,92,412],[1410,371,1403,351,1372,346,1358,335,1351,338,1351,346,1310,339,1320,331,1313,315,1307,310,1302,314,1304,323,1294,333,1326,354,1357,355,1367,373,1374,368,1394,382,1401,394,1399,406,1403,412,1414,414,1419,392,1410,382,1410,371],[96,422,92,414,85,423,94,430,96,422],[1439,442,1453,444,1455,433,1441,430,1432,420,1416,427,1411,416,1400,416,1398,426,1403,433,1414,434,1420,456,1439,442],[-637,466,-620,464,-629,460,-644,467,-640,470,-637,466],[-1235,485,-1257,488,-1281,500,-1284,508,-1258,503,-1235,485],[-561,507,-568,498,-561,502,-555,499,-558,496,-535,492,-538,485,-531,487,-526,475,-531,467,-542,468,-542,478,-554,469,-560,469,-553,474,-563,476,-593,476,-588,483,-592,485,-574,507,-554,516,-561,507],[-1327,540,-1317,541,-1320,530,-1312,522,-1331,534,-1332,542,-1327,540],[1436,507,1447,490,1432,493,1426,479,1435,468,1435,461,1427,467,1421,460,1422,510,1416,519,1417,533,1426,538,1422,542,1427,544,1436,507],[-68,523,-100,518,-92,529,-97,539,-67,552,-57,546,-68,523],[127,556,121,548,109,558,124,561,127,556],[-1530,571,-1540,567,-1547,575,-1532,580,-1521,576,-1530,571],[-30,586,-41,576,-20,577,-31,560,-21,559,5,529,17,527,11,518,14,513,-52,500,-58,502,-34,514,-53,520,-42,523,-48,528,-46,535,-31,534,-29,540,-48,548,-50,558,-56,553,-61,568,-50,586,-30,586],[-1656,599,-1675,602,-1657,603,-1656,599],[-793,622,-797,616,-804,620,-793,622],[-819,627,-831,622,-840,625,-833,629,-819,627],[-1717,638,-1687,633,-1695,630,-1716,633,-1717,638],[-852,657,-801,637,-810,634,-831,641,-855,631,-859,636,-872,635,-864,640,-859,657,-852,657],[-145,665,-147,658,-136,651,-187,635,-228,640,-218,644,-240,649,-222,654,-243,656,-237,663,-221,664,-206,657,-191,663,-145,665],[-759,671,-770,671,-772,676,-768,681,-751,680,-759,671],[-1750,666,-1743,663,-1746,671,-1719,669,-1699,660,-1725,654,-1730,643,-1762,654,-1784,654,-1789,657,-1787,661,-1799,659,-1794,654,-1800,650,-1800,690,-1749,672,-1750,666],[-956,691,-963,688,-998,694,-982,701,-956,691],[1800,708,1787,711,1800,715,1800,708],[-1787,709,-1800,708,-1800,715,-1776,713,-1787,709],[-905,695,-906,685,-892,693,-880,686,-883,679,-874,672,-856,688,-855,699,-826,697,-813,692,-820,681,-813,676,-814,671,-833,664,-858,666,-873,648,-899,640,-907,636,-908,630,-932,620,-942,609,-947,589,-932,588,-923,571,-909,573,-850,553,-823,551,-821,533,-799,512,-786,526,-798,547,-782,551,-765,565,-773,581,-785,588,-773,599,-781,623,-738,624,-714,611,-696,611,-693,590,-676,582,-662,588,-646,603,-614,570,-618,563,-573,546,-569,538,-558,533,-557,521,-600,502,-664,502,-711,468,-687,483,-651,492,-642,487,-651,481,-645,462,-615,459,-605,470,-598,459,-654,435,-661,436,-662,445,-644,453,-671,451,-670,448,-707,430,-708,423,-700,416,-737,409,-719,409,-740,408,-749,389,-755,395,-751,384,-759,372,-757,379,-763,392,-763,381,-770,382,-763,379,-757,356,-813,314,-813,300,-801,269,-804,252,-812,252,-817,259,-829,279,-829,291,-841,301,-851,296,-864,304,-892,303,-896,302,-892,293,-902,291,-938,297,-966,283,-974,274,-971,259,-979,224,-963,193,-944,181,-920,187,-908,193,-903,210,-871,215,-868,208,-878,183,-883,185,-884,165,-889,159,-850,160,-834,153,-838,111,-822,90,-814,88,-796,96,-768,86,-757,94,-749,111,-734,112,-718,124,-711,121,-719,114,-717,91,-710,99,-714,110,-702,114,-699,122,-682,106,-662,106,-649,101,-643,106,-619,107,-627,104,-624,99,-608,94,-607,86,-591,80,-571,60,-540,58,-513,42,-505,19,-500,17,-507,2,-504,-1,-486,-2,-486,-12,-478,-6,-449,-16,-446,-27,-434,-24,-400,-29,-372,-48,-356,-51,-347,-73,-351,-90,-387,-131,-393,-179,-409,-219,-420,-230,-446,-234,-476,-249,-485,-259,-489,-287,-538,-344,-562,-349,-584,-339,-585,-344,-572,-353,-568,-369,-577,-382,-592,-387,-623,-388,-621,-407,-627,-410,-651,-411,-650,-421,-638,-420,-635,-426,-652,-435,-656,-450,-673,-456,-676,-463,-656,-472,-660,-481,-691,-507,-682,-523,-708,-529,-710,-538,-749,-523,-756,-487,-741,-469,-756,-466,-747,-458,-744,-441,-732,-445,-727,-424,-734,-421,-737,-434,-743,-432,-732,-393,-736,-372,-732,-371,-714,-324,-715,-289,-709,-276,-702,-198,-704,-183,-715,-174,-760,-146,-798,-72,-812,-61,-809,-57,-814,-47,-798,-27,-810,-22,-809,-11,-801,8,-789,14,-784,26,-771,38,-782,83,-796,89,-805,81,-800,75,-809,72,-811,78,-835,84,-850,101,-851,96,-857,99,-857,111,-877,129,-875,133,-912,139,-947,162,-966,157,-1035,183,-1055,199,-1053,214,-1060,228,-1122,290,-1131,312,-1148,318,-1147,302,-1094,232,-1100,228,-1122,247,-1123,260,-1151,277,-1142,286,-1155,296,-1173,330,-1185,340,-1206,346,-1244,403,-1245,428,-1239,455,-1247,482,-1231,480,-1226,471,-1228,490,-1274,508,-1279,523,-1291,528,-1293,536,-1320,555,-1341,581,-1366,582,-1399,595,-1471,609,-1482,607,-1480,600,-1517,592,-1514,607,-1503,610,-1506,613,-1540,594,-1533,589,-1542,581,-1584,560,-1648,544,-1577,576,-1570,589,-1591,584,-1604,591,-1620,587,-1619,596,-1638,598,-1661,615,-1646,631,-1608,638,-1615,644,-1608,648,-1650,644,-1681,657,-1645,666,-1637,666,-1638,661,-1617,661,-1668,684,-1662,689,-1632,694,-1619,703,-1566,714,-1543,707,-1436,702,-1365,689,-1298,702,-1291,698,-1281,705,-1258,695,-1244,702,-1243,694,-1215,698,-1139,684,-1153,679,-1099,680,-1089,674,-1078,679,-1088,683,-1082,687,-1062,688,-1015,676,-984,678,-986,684,-977,686,-961,682,-961,673,-955,681,-947,681,-942,691,-965,701,-964,712,-952,719,-929,713,-915,702,-924,697,-905,695],[-1142,731,-1147,727,-1124,730,-1111,725,-1099,730,-1082,717,-1077,721,-1084,731,-1065,731,-1054,727,-1045,710,-1010,700,-1011,696,-1027,695,-1021,691,-1024,688,-1060,692,-1133,685,-1173,700,-1124,704,-1179,705,-1184,709,-1161,713,-1194,716,-1179,727,-1142,731],[-1045,734,-1054,728,-1069,735,-1045,734],[-763,731,-795,727,-809,733,-804,738,-781,737,-763,731],[-866,732,-858,725,-849,733,-823,738,-806,727,-807,721,-778,727,-742,718,-741,713,-722,716,-688,705,-670,692,-688,687,-619,669,-639,650,-667,664,-680,663,-681,657,-653,644,-647,634,-650,627,-688,637,-662,619,-710,629,-748,647,-777,642,-786,646,-779,653,-740,655,-743,658,-727,673,-729,677,-769,689,-762,691,-790,702,-849,700,-887,704,-895,708,-885,712,-899,712,-902,722,-894,731,-858,738,-866,732],[-1004,738,-974,738,-971,735,-981,730,-965,726,-967,717,-993,714,-1025,725,-1004,727,-1015,734,-1004,738],[1436,732,1399,734,1421,739,1436,732],[-932,728,-943,720,-954,721,-960,734,-945,741,-905,739,-932,728],[-1205,714,-1231,709,-1259,719,-1239,737,-1249,743,-1176,742,-1155,735,-1192,725,-1205,714],[1507,751,1496,747,1461,752,1507,751],[-936,750,-942,746,-968,749,-949,756,-936,750],[1451,756,1443,748,1390,746,1370,753,1375,759,1388,761,1451,756],[-985,767,-977,763,-982,750,-1025,756,-1026,763,-985,767],[-1082,762,-1059,760,-1057,755,-1063,750,-1122,744,-1139,747,-1118,752,-1177,752,-1154,765,-1091,755,-1105,764,-1096,768,-1082,762],[575,707,537,708,516,715,515,720,544,736,535,737,559,746,556,751,612,763,682,769,689,765,585,743,554,724,556,715,575,707],[-947,771,-916,768,-907,764,-910,761,-892,756,-811,757,-798,749,-819,744,-898,745,-924,748,-929,759,-939,763,-971,768,-967,772,-947,771],[-1162,776,-1163,769,-1171,765,-1229,761,-1191,775,-1162,776],[1070,770,1072,765,1111,767,1141,758,1139,753,1094,742,1130,740,1135,733,1156,738,1232,730,1233,737,1270,736,1286,730,1291,724,1285,720,1313,708,1323,718,1339,714,1399,715,1391,724,1405,728,1495,722,1530,708,1590,709,1598,705,1597,697,1609,694,1678,696,1696,687,1708,690,1700,697,1705,701,1757,699,1800,690,1800,650,1774,646,1794,630,1792,623,1774,625,1737,617,1703,599,1689,606,1663,598,1658,602,1635,599,1620,582,1632,576,1631,562,1621,561,1617,553,1621,549,1604,543,1600,532,1585,530,1582,519,1568,510,1554,554,1559,568,1568,578,1584,581,1637,611,1645,626,1633,625,1627,616,1601,605,1593,618,1567,614,1542,598,1550,591,1513,588,1513,595,1498,597,1485,592,1422,590,1351,547,1367,546,1382,538,1399,542,1413,531,1414,522,1406,512,1401,484,1382,463,1349,434,1335,428,1323,433,1300,419,1297,409,1275,398,1274,392,1295,368,1291,351,1265,344,1261,367,1269,369,1262,377,1247,381,1253,396,1243,399,1211,389,1222,404,1216,409,1190,393,1180,392,1175,387,1189,374,1197,372,1208,379,1224,375,1225,369,1211,367,1192,349,1202,344,1219,317,1219,309,1213,307,1221,298,1217,282,1211,281,1187,245,1159,228,1108,214,1104,203,1099,203,1099,214,1085,217,1059,198,1057,191,1089,153,1093,134,1092,117,1052,86,1051,99,1035,106,1026,122,1008,126,1010,134,1001,134,992,92,999,92,1005,74,1030,55,1042,13,1035,12,1014,28,1001,65,985,84,983,78,988,114,972,169,954,157,942,160,943,182,914,228,905,228,903,218,870,215,865,202,851,195,822,166,803,159,799,104,775,80,766,89,735,160,726,214,705,209,692,221,696,225,693,228,674,239,664,254,615,251,574,257,565,271,547,265,515,279,501,301,480,300,488,277,502,267,508,248,510,260,516,258,518,240,540,241,564,264,568,242,587,236,598,223,578,202,577,189,553,172,524,164,522,156,487,140,435,126,426,152,426,168,391,213,385,237,375,243,351,281,346,281,349,295,339,276,324,299,357,239,355,231,369,220,375,186,384,180,393,159,433,124,427,117,446,104,511,120,510,106,477,42,403,-26,392,-47,388,-65,394,-68,392,-85,405,-108,408,-147,395,-167,374,-176,348,-198,356,-237,326,-257,329,-262,322,-288,282,-328,258,-339,226,-339,196,-348,184,-341,179,-326,182,-317,152,-271,143,-221,118,-181,118,-158,136,-120,137,-107,119,-50,88,-11,98,31,94,37,85,48,59,43,43,63,19,61,-20,47,-46,52,-75,43,-90,48,-124,73,-148,109,-166,122,-167,136,-176,147,-165,161,-161,181,-170,219,-144,263,-96,299,-98,312,-93,326,-69,341,-59,358,-22,352,15,366,95,374,102,372,102,367,111,369,106,364,109,357,103,338,152,323,157,314,191,303,201,310,201,322,215,328,289,309,310,316,320,309,338,310,346,315,360,346,362,367,347,368,325,361,317,366,297,361,276,367,263,382,268,390,262,395,273,404,288,405,292,412,311,411,335,420,352,420,383,409,404,410,417,420,415,426,367,452,382,462,377,466,391,473,350,463,350,457,365,455,363,451,339,444,333,446,335,450,325,453,336,459,333,461,307,466,296,450,288,449,277,426,288,411,276,410,264,402,261,408,249,409,237,407,244,401,239,400,226,403,240,377,231,379,234,374,228,373,232,364,225,364,217,368,211,383,194,403,195,417,160,435,149,451,140,448,139,456,131,457,123,454,126,441,151,420,159,420,159,415,185,402,183,398,169,404,164,398,172,394,171,389,161,380,157,379,161,390,154,400,121,417,105,429,102,439,89,444,65,431,31,431,30,419,8,410,-3,393,1,387,-21,367,-44,367,-54,359,-65,369,-89,369,-88,383,-95,387,-88,408,-94,430,-80,437,-19,434,-14,440,-12,460,-30,476,-45,480,-46,487,-16,486,-19,498,-10,493,13,501,16,509,38,516,47,531,81,535,88,540,81,555,85,571,106,577,103,569,109,565,97,555,99,546,109,540,125,545,141,538,176,549,197,544,213,552,211,568,216,574,225,578,233,570,241,570,244,584,234,586,233,592,280,595,291,600,281,605,229,598,213,607,215,617,211,626,215,632,254,651,239,660,222,657,212,650,214,644,178,627,171,613,188,601,179,590,168,587,159,561,147,562,141,554,129,554,104,595,84,583,70,581,57,586,50,620,105,645,148,678,192,698,230,702,245,710,282,712,313,705,300,702,311,696,321,699,365,691,411,675,411,668,384,660,332,666,348,659,349,644,370,638,365,648,372,651,396,645,404,648,398,655,421,665,439,661,445,668,437,674,442,680,435,686,463,683,468,677,456,676,456,670,463,667,537,689,545,688,535,682,588,689,599,683,611,689,600,695,606,699,685,681,692,686,669,695,673,699,667,710,685,719,692,728,726,728,728,722,718,714,728,704,726,690,737,684,713,663,724,662,751,678,745,683,749,690,738,691,736,696,744,706,731,714,749,721,747,728,757,723,753,713,764,712,759,719,776,723,815,718,806,726,805,736,868,739,860,745,872,751,1008,764,1020,773,1044,777,1061,774,1047,771,1070,770],[491,413,504,403,496,402,489,388,492,376,508,369,538,370,539,390,531,393,534,400,527,400,529,409,547,410,537,421,529,419,528,411,525,428,513,431,503,446,513,445,513,452,530,453,530,469,512,470,491,464,467,446,491,413],[-1102,777,-1135,777,-1099,780,-1102,777],[247,779,207,777,214,779,208,783,229,785,247,779],[-1097,786,-1125,784,-1115,788,-1097,786],[-958,781,-981,781,-986,789,-956,784,-958,781],[-1001,783,-997,779,-1052,784,-1042,787,-1055,793,-1001,783],[1051,783,994,779,1021,793,1054,787,1051,783],[183,797,215,790,190,786,171,768,159,768,138,774,147,777,112,789,104,797,170,801,183,797],[254,804,274,801,230,794,174,803,254,804],[511,805,476,800,465,802,471,806,448,806,515,807,511,805],[999,789,950,790,912,803,959,813,1002,798,999,789],[-870,797,-858,793,-908,782,-929,783,-940,788,-931,794,-950,794,-967,802,-943,810,-947,812,-924,813,-878,803,-870,797],[-685,831,-618,826,-677,815,-655,815,-712,798,-769,793,-755,792,-762,790,-754,785,-798,772,-779,768,-806,762,-895,765,-896,770,-878,772,-883,779,-850,775,-880,784,-851,793,-869,803,-818,805,-876,805,-916,819,-855,827,-832,823,-824,829,-793,831,-685,831],[-271,835,-208,827,-319,822,-221,817,-232,812,-158,819,-122,813,-200,802,-177,801,-197,788,-197,776,-185,770,-217,766,-198,761,-196,752,-207,752,-194,743,-216,742,-204,738,-208,735,-236,733,-223,722,-248,723,-221,715,-218,707,-235,705,-255,714,-252,708,-264,702,-223,701,-277,685,-318,681,-342,667,-398,655,-412,635,-428,627,-424,619,-434,601,-483,609,-516,636,-523,652,-537,661,-533,668,-540,672,-530,684,-515,687,-509,699,-535,693,-547,696,-544,708,-514,706,-558,717,-547,726,-586,755,-613,761,-685,761,-714,770,-668,774,-733,780,-732,784,-657,794,-653,798,-680,801,-622,813,-627,818,-572,822,-530,819,-504,824,-445,817,-469,822,-468,826,-386,835,-271,835]];

const DEG = Math.PI / 180;
function ll2xyz(lon, lat) {
  const cf = Math.cos(lat * DEG);
  return [cf * Math.sin(lon * DEG), Math.sin(lat * DEG), cf * Math.cos(lon * DEG)];
}

const LAND_BB = LAND.map((r) => {
  let x0 = 1e9;
  let x1 = -1e9;
  let y0 = 1e9;
  let y1 = -1e9;
  for (let i = 0; i < r.length; i += 2) {
    if (r[i] < x0) x0 = r[i];
    if (r[i] > x1) x1 = r[i];
    if (r[i + 1] < y0) y0 = r[i + 1];
    if (r[i + 1] > y1) y1 = r[i + 1];
  }
  return [x0, x1, y0, y1];
});

// Degrees in, even-odd across all rings (holes work).
function isLand(lon, lat) {
  const x = lon * 10;
  const y = lat * 10;
  let inside = false;
  for (let k = 0; k < LAND.length; k++) {
    const b = LAND_BB[k];
    if (x < b[0] || x > b[1] || y < b[2] || y > b[3]) continue;
    const r = LAND[k];
    const n = r.length / 2;
    for (let i = 0, j = n - 1; i < n; j = i++) {
      const xi = r[i * 2];
      const yi = r[i * 2 + 1];
      const xj = r[j * 2];
      const yj = r[j * 2 + 1];
      if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
    }
  }
  return inside;
}

/* flag each stipple point as land/ocean once at load */
const landFlag = new Uint8Array(STIP_N);
for (let i = 0; i < STIP_N; i++) {
  const x = stip[i * 4];
  const y = stip[i * 4 + 1];
  const z = stip[i * 4 + 2];
  const lat = Math.asin(Math.max(-1, Math.min(1, y))) / DEG;
  const lon = Math.atan2(x, z) / DEG;
  landFlag[i] = isLand(lon, lat) ? 1 : 0;
}

/* coastlines: pre-subdivided 3D polylines on the sphere */
const COAST = LAND.map((r) => {
  const pts = [];
  const n = r.length / 2;
  let prev = ll2xyz(r[0] / 10, r[1] / 10);
  pts.push(prev[0], prev[1], prev[2]);
  for (let i = 1; i <= n; i++) {
    const ii = i % n;
    const cur = ll2xyz(r[ii * 2] / 10, r[ii * 2 + 1] / 10);
    const d = Math.max(-1, Math.min(1, prev[0] * cur[0] + prev[1] * cur[1] + prev[2] * cur[2]));
    const ang = Math.acos(d);
    const steps = Math.max(1, Math.ceil(ang / 0.02));
    for (let s = 1; s <= steps; s++) {
      const t = s / steps;
      const x = prev[0] + (cur[0] - prev[0]) * t;
      const y = prev[1] + (cur[1] - prev[1]) * t;
      const z = prev[2] + (cur[2] - prev[2]) * t;
      const l = Math.hypot(x, y, z) || 1;
      pts.push(x / l, y / l, z / l);
    }
    prev = cur;
  }
  return new Float32Array(pts);
});

/* Anchored grid dots — fixed positions ON the sphere, cached per M/P/step.
   Dots are glued to the globe like paint: rotation moves them, never
   re-seats them, so lines can't crawl or "regenerate" mid-spin. */
let gridCache = { key: "", pts: null };
function gridDots(M, P, step) {
  const key = M + "|" + P + "|" + step.toFixed(4);
  if (gridCache.key === key) return gridCache.pts;
  const out = [];
  for (let j = 0; j < M; j++) {
    const lon = (j * Math.PI) / M;
    const cl = Math.cos(lon);
    const sl = Math.sin(lon);
    const n = Math.max(8, Math.round((Math.PI * 2) / step));
    for (let i = 0; i < n; i++) {
      const t = (i / n) * Math.PI * 2;
      const st = Math.sin(t);
      out.push(st * cl, Math.cos(t), st * sl);
    }
  }
  for (let k = 1; k <= P; k++) {
    const lat = -Math.PI / 2 + (k * Math.PI) / (P + 1);
    const r = Math.cos(lat);
    const y = Math.sin(lat);
    const n = Math.max(6, Math.round((Math.PI * 2 * r) / step));
    for (let i = 0; i < n; i++) {
      const t = (i / n) * Math.PI * 2;
      out.push(r * Math.cos(t), y, r * Math.sin(t));
    }
  }
  gridCache = { key, pts: new Float32Array(out) };
  return gridCache.pts;
}

/* anchored coastline dots — walked once along the polylines in object
   space at fixed 3D arc spacing, cached per step */
let coastCache = { key: "", pts: null };
function coastDots(step) {
  const key = step.toFixed(4);
  if (coastCache.key === key) return coastCache.pts;
  const out = [];
  for (const pts of COAST) {
    let acc = step;
    for (let i = 3; i < pts.length; i += 3) {
      const dx = pts[i] - pts[i - 3];
      const dy = pts[i + 1] - pts[i - 2];
      const dz = pts[i + 2] - pts[i - 1];
      acc += Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (acc >= step) {
        acc = 0;
        out.push(pts[i], pts[i + 1], pts[i + 2]);
      }
    }
  }
  coastCache = { key, pts: new Float32Array(out) };
  return coastCache.pts;
}

/* Region markers: pulsing purple points glued to real locations on the
   sphere — they rotate with the globe and hide behind the horizon. No
   labels, just the pulse. */
const MARKERS = [
  [-0.1, 51.5], // EU West — London
  [8.7, 50.1], // EU Central — Frankfurt
  [-77.5, 38.9], // US East — N. Virginia
  [-122.7, 45.5], // US West — Oregon
  [-100.4, 20.6], // Mexico — Querétaro
  [-46.6, -23.5], // Brazil — São Paulo
  [31.2, 30.0], // North Africa — Cairo
  [72.9, 19.1], // India — Mumbai
  [103.8, 1.35], // Asia — Singapore
  [139.7, 35.7], // Japan — Tokyo
  [151.2, -33.9], // Australia — Sydney
].map(([lon, lat]) => ll2xyz(lon, lat));

const PULSE_S = 2.4; // one ring per marker every PULSE_S seconds, staggered

// The tunable options and their data-attribute names.
const OPTIONS = [
  { key: "size", attr: "size", def: 0.78 },
  { key: "pitch", attr: "pitch", def: 2 },
  { key: "tiltX", attr: "tilt-x", def: 0.42 },
  { key: "tiltZ", attr: "tilt-z", def: -0.25 },
  { key: "speed", attr: "speed", def: 0.25 },
  { key: "meridians", attr: "meridians", def: 9 },
  { key: "parallels", attr: "parallels", def: 9 },
  { key: "density", attr: "density", def: 40 },
  { key: "shade", attr: "shade", def: 30 },
  { key: "land", attr: "land", def: 55 },
  { key: "ocean", attr: "ocean", def: 20 },
  { key: "offsetX", attr: "offset-x", def: 0 },
  { key: "offsetY", attr: "offset-y", def: 0 },
];

export const DitherGlobe = {
  mounted() {
    this.canvas = this.el;
    this.ctx = this.canvas.getContext("2d");
    this.host = this.canvas.parentElement;
    this.reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    this.raf = null;
    this.visible = false;
    this.spin = 0;
    this.pulseT = 0;
    this.drag = IDENTITY;

    this.opts = {};
    for (const o of OPTIONS) {
      const raw = this.el.dataset[o.attr.replace(/-(\w)/g, (_, c) => c.toUpperCase())];
      const n = raw === undefined ? NaN : Number(raw);
      this.opts[o.key] = Number.isFinite(n) ? n : o.def;
    }

    this.resolveColors = () => {
      this.shades = [
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-shallow"),
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-mid"),
        resolveTokenColor(this.host, "--marketing-cache-globe-dither-deep"),
      ];
      this.markerShade = resolveTokenColor(this.host, "--marketing-cache-globe-marker");
    };
    this.resolveColors();
    this.offThemeChange = onThemeChange(() => {
      this.resolveColors();
      this.render();
    });

    this.resize = () => {
      const rect = this.host.getBoundingClientRect();
      const dpr = Math.min(window.devicePixelRatio || 1, 2);
      this.w = Math.max(1, Math.round(rect.width));
      this.h = Math.max(1, Math.round(rect.height));
      this.canvas.width = this.w * dpr;
      this.canvas.height = this.h * dpr;
      this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      this.render();
    };
    this.observer = new ResizeObserver(this.resize);
    this.observer.observe(this.host);
    this.resize();

    // Spin only while on screen (and never under reduced motion — the
    // globe then holds the frame it mounted with).
    this.viewObserver = new IntersectionObserver(
      ([entry]) => {
        this.visible = entry.isIntersecting;
        if (this.visible && !this.reduced) this.start();
        else this.stop();
      },
      { threshold: 0.05 },
    );
    this.viewObserver.observe(this.host);

    /* drag to rotate (trackball, view space) */
    this.dragging = false;
    this.onPointerDown = (e) => {
      this.dragging = true;
      this.lx = e.clientX;
      this.ly = e.clientY;
      this.canvas.classList.add("dragging");
      this.canvas.setPointerCapture(e.pointerId);
    };
    this.onPointerMove = (e) => {
      if (!this.dragging) return;
      const dx = e.clientX - this.lx;
      const dy = e.clientY - this.ly;
      this.lx = e.clientX;
      this.ly = e.clientY;
      const len = Math.hypot(dx, dy);
      if (len > 0) {
        const k = 3.1 / Math.min(this.w, this.h);
        this.drag = matMul(rotAxis(dy, dx, 0, len * k), this.drag);
        if (this.raf === null) this.render();
      }
    };
    this.onPointerUp = () => {
      this.dragging = false;
      this.canvas.classList.remove("dragging");
    };
    this.canvas.addEventListener("pointerdown", this.onPointerDown);
    this.canvas.addEventListener("pointermove", this.onPointerMove);
    this.canvas.addEventListener("pointerup", this.onPointerUp);
    this.canvas.addEventListener("pointercancel", this.onPointerUp);

    this.render();
  },

  destroyed() {
    if (this.offThemeChange) this.offThemeChange();
    if (this.observer) this.observer.disconnect();
    if (this.viewObserver) this.viewObserver.disconnect();
    this.stop();
    this.canvas.removeEventListener("pointerdown", this.onPointerDown);
    this.canvas.removeEventListener("pointermove", this.onPointerMove);
    this.canvas.removeEventListener("pointerup", this.onPointerUp);
    this.canvas.removeEventListener("pointercancel", this.onPointerUp);
  },

  start() {
    if (this.raf !== null) return;
    this.lastTime = performance.now();
    // Full rAF rate (~60fps): with chunky pitch cells a quantized cadence
    // reads as jitter, so the rotation advances every frame — the dots
    // still snap to the cell grid, they just step far more often.
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      const dt = Math.min((now - this.lastTime) / 1000, 0.25);
      this.lastTime = now;
      if (!this.dragging) this.spin += this.opts.speed * dt;
      this.pulseT += dt;
      this.render();
    };
    this.raf = requestAnimationFrame(tick);
  },

  stop() {
    if (this.raf !== null) {
      cancelAnimationFrame(this.raf);
      this.raf = null;
    }
  },

  // drag (view) * tilt (posing) * spin (own pole) — sliders keep working
  // after a drag, and the spin never disturbs the tilt.
  rotation() {
    const tilt = matMul(rotAxis(1, 0, 0, this.opts.tiltX), rotAxis(0, 0, 1, this.opts.tiltZ));
    return matMul(this.drag, matMul(tilt, rotAxis(0, 1, 0, this.spin)));
  },

  /* Generate the globe's dots: {x, y} in unit sphere space plus a signal
     n in 0..1 — how deep into the shade ramp the dot sits. The wireframe
     and coastlines are anchored to the sphere; the stipple fill uses each
     point's stable rand as its density threshold, so the grain holds
     still while the globe turns under it. */
  buildDots() {
    const dots = [];
    const R = this.rotation();
    const M = Math.round(this.opts.meridians);
    const P = Math.round(this.opts.parallels);
    const spacing = 0.055 - (this.opts.density / 100) * 0.041;
    const shadeAmt = this.opts.shade / 100;
    const landAmt = this.opts.land / 100;
    const oceanAmt = this.opts.ocean / 100;
    const m0 = R[0];
    const m1 = R[1];
    const m2 = R[2];
    const m3 = R[3];
    const m4 = R[4];
    const m5 = R[5];
    const m6 = R[6];
    const m7 = R[7];
    const m8 = R[8];
    const L0 = L[0];
    const L1 = L[1];
    const L2 = L[2];

    // rotate anchored dots, cull the back hemisphere, shade by darkness
    const anchored = (pts, base, span) => {
      for (let i = 0; i < pts.length; i += 3) {
        const x = pts[i];
        const y = pts[i + 1];
        const z = pts[i + 2];
        const wz = m6 * x + m7 * y + m8 * z;
        if (wz <= 0.015) continue;
        const wx = m0 * x + m1 * y + m2 * z;
        const wy = m3 * x + m4 * y + m5 * z;
        let b = (wx * L0 + wy * L1 + wz * L2) * 0.5 + 0.5;
        if (b < 0) b = 0;
        else if (b > 1) b = 1;
        dots.push({ x: wx, y: wy, n: base + span * (1 - b) });
      }
    };
    anchored(gridDots(M, P, spacing), 0.35, 0.45);
    if (landAmt > 0) anchored(coastDots(spacing * 0.62), 0.55, 0.45);

    // surface stipple — land fill + ocean grain + terminator shading
    if (shadeAmt > 0 || landAmt > 0 || oceanAmt > 0) {
      for (let i = 0; i < STIP_N; i++) {
        const x = stip[i * 4];
        const y = stip[i * 4 + 1];
        const z = stip[i * 4 + 2];
        // depth-only test first — skips ~half the points before full transform
        const wz = m6 * x + m7 * y + m8 * z;
        if (wz < 0.03) continue;
        const wx = m0 * x + m1 * y + m2 * z;
        const wy = m3 * x + m4 * y + m5 * z;
        let b = (wx * L0 + wy * L1 + wz * L2) * 0.5 + 0.5;
        if (b < 0) b = 0;
        else if (b > 1) b = 1;
        const d = 1 - b;
        const rnd = stip[i * 4 + 3];
        if (landAmt > 0 && landFlag[i]) {
          // land: reads on the lit side too, thickens toward shadow
          if (landAmt * (0.55 + 0.6 * d) > rnd) dots.push({ x: wx, y: wy, n: 0.45 + 0.55 * d });
        } else if (shadeAmt > 0 && i % 3 === 0 && Math.pow(d, 2.6) * shadeAmt * 1.35 > rnd) {
          dots.push({ x: wx, y: wy, n: 0.3 + 0.5 * d });
        } else if (oceanAmt > 0 && oceanAmt * 0.5 * (0.55 + 0.55 * d) > rnd) {
          // fine, sparse water grain — shallowest shades, so land stays darker
          dots.push({ x: wx, y: wy, n: 0.2 + 0.3 * d });
        }
      }
    }
    return dots;
  },

  render() {
    const { ctx, w, h, shades } = this;
    if (!w || !h) return;
    ctx.clearRect(0, 0, w, h);
    const rad = (Math.min(w, h) / 2) * this.opts.size;
    const cx = w / 2 + this.opts.offsetX;
    const cy = h / 2 + this.opts.offsetY;
    const pitch = Math.max(1, Math.round(this.opts.pitch));
    const dots = this.buildDots();
    for (let i = 0; i < dots.length; i++) {
      const d = dots[i];
      // Snap to the pitch cell grid — the dither texture's chunky grain.
      const gx = Math.round((cx + d.x * rad) / pitch);
      const gy = Math.round((cy - d.y * rad) / pitch);
      // Seamless ramp: the signal maps to a continuous position across
      // the three shades, and each dot dithers between its two nearest
      // shades via the stable cell hash — the colors interleave instead
      // of stacking into visible bands.
      const s = Math.min(2, d.n * 2);
      const lo = Math.floor(s);
      const hi = Math.min(2, lo + 1);
      const shade = s - lo > noise2(gx + 31, gy + 17) ? shades[hi] : shades[lo];
      ctx.fillStyle = `rgb(${shade[0]}, ${shade[1]}, ${shade[2]})`;
      ctx.fillRect(gx * pitch, gy * pitch, pitch, pitch);
    }
    this.renderMarkers(pitch, rad, cx, cy);
  },

  /* Pulsing region markers, drawn on top of the globe as plain vector
     shapes (no dither): a solid purple core plus an expanding stroked
     ring that fades out with alpha as it grows. Core and ring live on the
     sphere's tangent plane at the marker, so they project as foreshortened
     ellipses hugging the surface — tilting with the globe and squashing
     toward the limb — instead of flat screen circles. Markers fade out
     near the horizon and under prefers-reduced-motion only the static
     cores show. */
  renderMarkers(pitch, rad, cx, cy) {
    const { ctx } = this;
    const R = this.rotation();
    const [mr, mg, mb] = this.markerShade;
    const color = `rgb(${mr}, ${mg}, ${mb})`;
    const coreR = Math.max(pitch * 1.5, rad * 0.028) / rad;
    const maxRing = coreR + 0.11;
    for (let i = 0; i < MARKERS.length; i++) {
      const [x, y, z] = MARKERS[i];
      const wz = R[6] * x + R[7] * y + R[8] * z;
      if (wz <= 0.12) continue;
      const limb = Math.min(1, (wz - 0.12) / 0.3);
      const wx = R[0] * x + R[1] * y + R[2] * z;
      const wy = R[3] * x + R[4] * y + R[5] * z;
      const px = cx + wx * rad;
      const py = cy - wy * rad;
      // Tangent basis at the marker (view space): t1 ⟂ the surface normal
      // and horizontal-ish, t2 = n × t1. Their screen projections become
      // the canvas transform, so a unit circle drawn under it lands as the
      // tangent-plane ellipse.
      let t1x = wz;
      let t1z = -wx;
      const t1l = Math.hypot(t1x, t1z) || 1;
      t1x /= t1l;
      t1z /= t1l;
      const t2x = wy * t1z;
      const t2y = wz * t1x - wx * t1z;
      const a = t1x * rad;
      const b = t2x * rad;
      const d = -t2y * rad;
      if (Math.abs(a * d) < 1e-6) continue;
      ctx.save();
      ctx.transform(a, 0, b, d, px, py);
      ctx.fillStyle = color;
      ctx.globalAlpha = limb;
      ctx.beginPath();
      ctx.arc(0, 0, coreR, 0, Math.PI * 2);
      ctx.fill();
      if (!this.reduced) {
        // Stagger the phases so the pulses ripple around the globe
        // instead of firing in unison.
        const t = (this.pulseT / PULSE_S + i * 0.37) % 1;
        const ringR = coreR + t * (maxRing - coreR);
        ctx.strokeStyle = color;
        ctx.globalAlpha = (1 - t) * 0.9 * limb;
        ctx.lineWidth = Math.max(1.25, pitch) / rad;
        ctx.beginPath();
        ctx.arc(0, 0, ringR, 0, Math.PI * 2);
        ctx.stroke();
      }
      ctx.restore();
    }
  },
};
