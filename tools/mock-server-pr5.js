#!/usr/bin/env node
/**
 * Мок-сервер учебного API «Библиотека» — вариант для практической работы 5.
 *
 * Это копия лекционного mock-server.js (оригинал не изменён) с добавками,
 * которые нужны заданию и которых в оригинале нет. Все добавки помечены
 * комментарием «ПР5»:
 *   1. Любой запрос к ресурсам требует токен (без него 401). В оригинале
 *      чтение открыто всем, поэтому истёкший токен на чтении не проявлялся.
 *   2. PATCH /api/users/{id} — смена роли (только admin).
 *   3. POST /api/loans/{id}/extend — продление выдачи читателем.
 *   4. Читатель видит в /api/readers только собственную запись.
 *   5. Пароль при регистрации должен содержать специальный символ.
 *
 *
 * Реализует контракт из файла КОНТРАКТ-API.md.
 * Зависимостей нет — нужен только Node.js 18 или новее.
 *
 *   node mock-server.js
 *   node mock-server.js --port 8080 --origin http://localhost:5555
 *
 * Данные хранятся в памяти и сбрасываются при перезапуске
 * либо запросом POST /api/__reset
 *
 * Учебные возможности:
 *   ?__delay=1500   задержка ответа в миллисекундах (проверка индикатора загрузки)
 *   ?__fail=500     принудительный код ошибки (проверка обработки ошибок)
 */

'use strict';

const http = require('node:http');
const crypto = require('node:crypto');

// ─────────────────────────── параметры запуска ───────────────────────────

const args = process.argv.slice(2);
function arg(name, fallback) {
  const i = args.indexOf('--' + name);
  return i !== -1 && args[i + 1] ? args[i + 1] : fallback;
}

const PORT = Number(arg('port', 8080));
const ORIGIN = arg('origin', '*');
const SECRET = 'учебный-ключ-не-для-продакшена';
const ACCESS_TTL = Number(arg('ttl', 900));      // секунд
const REFRESH_TTL = 60 * 60 * 24 * 7;

// ─────────────────────────────── токены ───────────────────────────────

function b64url(buf) {
  return Buffer.from(buf).toString('base64url');
}

function sign(payload) {
  // jti делает каждый токен уникальным. Без него два токена, выпущенных
  // в одну и ту же секунду для одного пользователя, совпадут побайтово,
  // и отзыв старого токена обновления отзовёт заодно и новый.
  const withId = { ...payload, jti: crypto.randomUUID() };
  const body = b64url(JSON.stringify(withId));
  const mac = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  return body + '.' + mac;
}

function verify(token) {
  if (typeof token !== 'string' || !token.includes('.')) return null;
  const [body, mac] = token.split('.');
  const expected = crypto.createHmac('sha256', SECRET).update(body).digest('base64url');
  if (mac !== expected) return null;
  let payload;
  try {
    payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
  if (payload.exp && payload.exp * 1000 < Date.now()) return null;
  return payload;
}

// ─────────────────────────────── данные ───────────────────────────────

let db;

function seed() {
  db = {
    seq: {},
    publishers: [],
    authors: [],
    genres: [],
    books: [],
    readers: [],
    cards: [],
    loans: [],
    users: [],
    refreshTokens: new Set(),
  };

  const P = (name, city, foundedYear) => push('publishers', { name, city, foundedYear });
  const A = (fullName, birthYear, country) => push('authors', { fullName, birthYear, country });
  const G = (name, description) => push('genres', { name, description });

  const ast = P('АСТ', 'Москва', 1990);
  const eksmo = P('Эксмо', 'Москва', 1991);
  const azbuka = P('Азбука', 'Санкт-Петербург', 1995);
  const piter = P('Питер', 'Санкт-Петербург', 1991);

  const tolstoy = A('Толстой Л. Н.', 1828, 'Россия');
  const dost = A('Достоевский Ф. М.', 1821, 'Россия');
  const bulgakov = A('Булгаков М. А.', 1891, 'Россия');
  const strugatsky1 = A('Стругацкий А. Н.', 1925, 'СССР');
  const strugatsky2 = A('Стругацкий Б. Н.', 1933, 'СССР');
  const orwell = A('Оруэлл Дж.', 1903, 'Великобритания');
  const bradbury = A('Брэдбери Р.', 1920, 'США');
  const remarque = A('Ремарк Э. М.', 1898, 'Германия');

  const roman = G('Роман', 'Крупная форма повествовательной прозы');
  const fantastika = G('Фантастика', 'Произведения с элементами вымысла о будущем и науке');
  const classic = G('Классика', 'Произведения, вошедшие в литературный канон');
  const antiutopia = G('Антиутопия', 'Изображение общества, движущегося к катастрофе');
  const detective = G('Детектив', 'Расследование преступления как основа сюжета');
  const tech = G('Техническая литература', 'Учебные и справочные издания');

  const B = (title, isbn, year, pages, publisherId, authorIds, genreIds, copiesTotal) =>
    push('books', {
      title, isbn, year, pages, publisherId, authorIds, genreIds,
      copiesTotal, copiesAvailable: copiesTotal,
    });

  B('Война и мир', '978-5-17-118366-4', 1869, 1300, ast, [tolstoy], [roman, classic], 4);
  B('Анна Каренина', '978-5-17-090620-1', 1877, 864, ast, [tolstoy], [roman, classic], 3);
  B('Преступление и наказание', '978-5-389-06003-6', 1866, 672, azbuka, [dost], [roman, classic], 5);
  B('Идиот', '978-5-389-07773-7', 1869, 640, azbuka, [dost], [roman, classic], 2);
  B('Братья Карамазовы', '978-5-04-089115-8', 1880, 1024, eksmo, [dost], [roman, classic], 2);
  B('Мастер и Маргарита', '978-5-17-084362-9', 1967, 480, ast, [bulgakov], [roman, fantastika, classic], 6);
  B('Собачье сердце', '978-5-17-088237-6', 1925, 192, ast, [bulgakov], [roman, fantastika], 4);
  B('Пикник на обочине', '978-5-17-096909-1', 1972, 288, ast, [strugatsky1, strugatsky2], [fantastika], 3);
  B('Трудно быть богом', '978-5-17-095832-3', 1964, 224, ast, [strugatsky1, strugatsky2], [fantastika], 3);
  B('Понедельник начинается в субботу', '978-5-17-097584-9', 1965, 320, ast, [strugatsky1, strugatsky2], [fantastika], 2);
  B('1984', '978-5-17-080115-5', 1949, 320, ast, [orwell], [antiutopia, fantastika], 5);
  B('Скотный двор', '978-5-17-097584-1', 1945, 144, ast, [orwell], [antiutopia], 3);
  B('451 градус по Фаренгейту', '978-5-04-004643-9', 1953, 272, eksmo, [bradbury], [antiutopia, fantastika], 4);
  B('Марсианские хроники', '978-5-04-089116-5', 1950, 352, eksmo, [bradbury], [fantastika], 2);
  B('Вино из одуванчиков', '978-5-04-093471-6', 1957, 320, eksmo, [bradbury], [roman], 3);
  B('Три товарища', '978-5-17-088179-9', 1936, 480, ast, [remarque], [roman], 4);
  B('На Западном фронте без перемен', '978-5-17-088180-5', 1929, 288, ast, [remarque], [roman, classic], 3);
  B('Триумфальная арка', '978-5-17-088181-2', 1945, 480, ast, [remarque], [roman], 2);
  B('Чистая архитектура', '978-5-4461-0772-8', 2017, 352, piter, [], [tech], 2);
  B('Совершенный код', '978-5-4461-0906-7', 2004, 896, piter, [], [tech], 1);

  const readerNames = [
    ['Смирнов П. А.', 'smirnov@example.com', '+7 900 100-10-01'],
    ['Кузнецова М. И.', 'kuznetsova@example.com', '+7 900 100-10-02'],
    ['Попов Д. С.', 'popov@example.com', '+7 900 100-10-03'],
    ['Васильева Е. О.', 'vasileva@example.com', '+7 900 100-10-04'],
    ['Новиков А. В.', 'novikov@example.com', '+7 900 100-10-05'],
    ['Морозова Т. Н.', 'morozova@example.com', '+7 900 100-10-06'],
  ];

  readerNames.forEach(([fullName, email, phone], i) => {
    const readerId = push('readers', { fullName, email, phone });
    push('cards', {
      readerId,
      number: 'RC-' + String(readerId).padStart(6, '0'),
      issuedAt: iso(2026, 1, 15 + i),
      expiresAt: iso(2027, 1, 15 + i),
    });
  });

  // несколько выдач, в том числе просроченная
  makeLoan(1, 1, -20, 14);   // просрочена
  makeLoan(2, 6, -5, 14);    // активна
  makeLoan(3, 11, -30, 14, true); // возвращена
  makeLoan(1, 8, -3, 14);    // ПР5: активная выдача читателя №1, чтобы было что продлевать

  push('users', { username: 'admin', passwordHash: hash('admin123'), fullName: 'Администратор', email: 'admin@library.local', role: 'admin', readerId: null });
  push('users', { username: 'librarian', passwordHash: hash('librarian123'), fullName: 'Петрова А. С.', email: 'petrova@library.local', role: 'librarian', readerId: null });
  push('users', { username: 'reader', passwordHash: hash('reader123'), fullName: 'Смирнов П. А.', email: 'smirnov@example.com', role: 'reader', readerId: 1 });
}

function push(collection, obj) {
  db.seq[collection] = (db.seq[collection] || 0) + 1;
  const id = db.seq[collection];
  db[collection].push({ id, ...obj, createdAt: new Date().toISOString(), deletedAt: null });
  return id;
}

function iso(y, m, d) {
  return new Date(Date.UTC(y, m - 1, d)).toISOString();
}

function hash(password) {
  return crypto.createHash('sha256').update(password + SECRET).digest('hex');
}

function makeLoan(readerId, bookId, issuedDaysAgo, days, returned = false) {
  const issuedAt = new Date(Date.now() + issuedDaysAgo * 86400000);
  const dueAt = new Date(issuedAt.getTime() + days * 86400000);
  const id = push('loans', {
    readerId,
    bookId,
    issuedAt: issuedAt.toISOString(),
    dueAt: dueAt.toISOString(),
    returnedAt: returned ? new Date().toISOString() : null,
  });
  if (!returned) {
    const book = db.books.find((b) => b.id === bookId);
    if (book) book.copiesAvailable = Math.max(0, book.copiesAvailable - 1);
  }
  return id;
}

// ──────────────────────── развёртывание объектов ────────────────────────

function slimPublisher(id) {
  const p = db.publishers.find((x) => x.id === id);
  return p ? { id: p.id, name: p.name } : null;
}

function expandBook(b) {
  return {
    id: b.id,
    title: b.title,
    isbn: b.isbn,
    year: b.year,
    pages: b.pages,
    publisher: slimPublisher(b.publisherId),
    authors: b.authorIds
      .map((id) => db.authors.find((a) => a.id === id))
      .filter(Boolean)
      .map((a) => ({ id: a.id, fullName: a.fullName })),
    genres: b.genreIds
      .map((id) => db.genres.find((g) => g.id === id))
      .filter(Boolean)
      .map((g) => ({ id: g.id, name: g.name })),
    copiesTotal: b.copiesTotal,
    copiesAvailable: b.copiesAvailable,
    createdAt: b.createdAt,
    deletedAt: b.deletedAt,
  };
}

function expandReader(r) {
  const card = db.cards.find((c) => c.readerId === r.id && !c.deletedAt);
  return {
    id: r.id,
    fullName: r.fullName,
    email: r.email,
    phone: r.phone,
    card: card
      ? { id: card.id, number: card.number, issuedAt: card.issuedAt, expiresAt: card.expiresAt }
      : null,
    createdAt: r.createdAt,
    deletedAt: r.deletedAt,
  };
}

function expandLoan(l) {
  const reader = db.readers.find((r) => r.id === l.readerId);
  const book = db.books.find((b) => b.id === l.bookId);
  let status = 'active';
  if (l.returnedAt) status = 'returned';
  else if (new Date(l.dueAt) < new Date()) status = 'overdue';
  return {
    id: l.id,
    reader: reader ? { id: reader.id, fullName: reader.fullName } : null,
    book: book ? { id: book.id, title: book.title } : null,
    issuedAt: l.issuedAt,
    dueAt: l.dueAt,
    returnedAt: l.returnedAt,
    status,
    deletedAt: l.deletedAt,
  };
}

function expandUser(u) {
  return { id: u.id, username: u.username, fullName: u.fullName, email: u.email, role: u.role, readerId: u.readerId };
}

const EXPANDERS = {
  books: expandBook,
  readers: expandReader,
  loans: expandLoan,
  authors: (a) => a,
  genres: (g) => g,
  publishers: (p) => p,
};

// ─────────────────────────── общие операции ───────────────────────────

function searchableText(collection, item) {
  switch (collection) {
    case 'books': return [item.title, item.isbn].join(' ');
    case 'authors': return [item.fullName, item.country].join(' ');
    case 'genres': return [item.name, item.description].join(' ');
    case 'publishers': return [item.name, item.city].join(' ');
    case 'readers': return [item.fullName, item.email, item.phone].join(' ');
    default: return '';
  }
}

function applyFilters(collection, rows, q) {
  let result = rows;

  if (q.search) {
    const needle = String(q.search).toLowerCase();
    result = result.filter((x) => searchableText(collection, x).toLowerCase().includes(needle));
  }

  if (collection === 'books') {
    if (q.genreId) result = result.filter((b) => b.genreIds.includes(Number(q.genreId)));
    if (q.authorId) result = result.filter((b) => b.authorIds.includes(Number(q.authorId)));
    if (q.publisherId) result = result.filter((b) => b.publisherId === Number(q.publisherId));
    if (q.yearFrom) result = result.filter((b) => b.year >= Number(q.yearFrom));
    if (q.yearTo) result = result.filter((b) => b.year <= Number(q.yearTo));
    if (q.available === 'true') result = result.filter((b) => b.copiesAvailable > 0);
  }

  if (collection === 'loans') {
    if (q.readerId) result = result.filter((l) => l.readerId === Number(q.readerId));
    if (q.bookId) result = result.filter((l) => l.bookId === Number(q.bookId));
    if (q.status) {
      result = result.filter((l) => expandLoan(l).status === q.status);
    }
  }

  return result;
}

function applySort(rows, sort) {
  if (!sort) return rows;
  const [field, dirRaw] = String(sort).split(',');
  const dir = (dirRaw || 'asc').toLowerCase() === 'desc' ? -1 : 1;
  return [...rows].sort((a, b) => {
    const av = a[field];
    const bv = b[field];
    if (av == null && bv == null) return 0;
    if (av == null) return 1;
    if (bv == null) return -1;
    if (typeof av === 'number' && typeof bv === 'number') return (av - bv) * dir;
    return String(av).localeCompare(String(bv), 'ru') * dir;
  });
}

function paginate(rows, q) {
  const page = Math.max(1, Number(q.page) || 1);
  const size = Math.min(100, Math.max(1, Number(q.size) || 10));
  const total = rows.length;
  const totalPages = Math.max(1, Math.ceil(total / size));
  return {
    items: rows.slice((page - 1) * size, page * size),
    page,
    size,
    total,
    totalPages,
  };
}

// ─────────────────────────────── валидация ───────────────────────────────

function validate(collection, body, id = null) {
  const e = {};
  const str = (v) => (typeof v === 'string' ? v.trim() : '');

  if (collection === 'books') {
    if (!str(body.title)) e.title = 'Укажите название';
    else if (str(body.title).length > 200) e.title = 'Не длиннее 200 символов';

    if (!str(body.isbn)) e.isbn = 'Укажите ISBN';
    else {
      const dup = db.books.find((b) => b.isbn === str(body.isbn) && b.id !== id && !b.deletedAt);
      if (dup) e.isbn = 'Книга с таким ISBN уже существует';
    }

    const year = Number(body.year);
    if (!Number.isInteger(year)) e.year = 'Год — целое число';
    else if (year < 1450) e.year = 'Год не может быть раньше 1450';
    else if (year > new Date().getFullYear()) e.year = 'Год не может быть в будущем';

    if (body.pages != null && (!Number.isInteger(Number(body.pages)) || Number(body.pages) < 1)) {
      e.pages = 'Число страниц — положительное целое';
    }
    if (body.publisherId != null && !db.publishers.find((p) => p.id === Number(body.publisherId) && !p.deletedAt)) {
      e.publisherId = 'Издательство не найдено';
    }
    const copies = Number(body.copiesTotal);
    if (!Number.isInteger(copies) || copies < 0) e.copiesTotal = 'Число экземпляров — целое, не меньше нуля';
  }

  if (collection === 'authors') {
    if (!str(body.fullName)) e.fullName = 'Укажите имя автора';
    if (body.birthYear != null) {
      const y = Number(body.birthYear);
      if (!Number.isInteger(y) || y < 1 || y > new Date().getFullYear()) e.birthYear = 'Некорректный год рождения';
    }
  }

  if (collection === 'genres') {
    if (!str(body.name)) e.name = 'Укажите название жанра';
    else {
      const dup = db.genres.find((g) => g.name.toLowerCase() === str(body.name).toLowerCase() && g.id !== id && !g.deletedAt);
      if (dup) e.name = 'Такой жанр уже существует';
    }
  }

  if (collection === 'publishers') {
    if (!str(body.name)) e.name = 'Укажите название издательства';
    if (body.foundedYear != null) {
      const y = Number(body.foundedYear);
      if (!Number.isInteger(y) || y < 1400 || y > new Date().getFullYear()) e.foundedYear = 'Некорректный год основания';
    }
  }

  if (collection === 'readers') {
    if (!str(body.fullName)) e.fullName = 'Укажите ФИО читателя';
    if (!str(body.email)) e.email = 'Укажите адрес почты';
    else if (!/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(str(body.email))) e.email = 'Некорректный адрес почты';
    else {
      const dup = db.readers.find((r) => r.email === str(body.email) && r.id !== id && !r.deletedAt);
      if (dup) e.email = 'Читатель с такой почтой уже зарегистрирован';
    }
  }

  return e;
}


// ──────────────────────────── HTTP-обвязка ────────────────────────────

function cors(res) {
  res.setHeader('Access-Control-Allow-Origin', ORIGIN);
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, PUT, PATCH, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Max-Age', '86400');
  res.setHeader('Vary', 'Origin');
}

function send(res, status, payload) {
  cors(res);
  if (payload === undefined || status === 204) {
    res.writeHead(204);
    res.end();
    return;
  }
  const body = JSON.stringify(payload, null, 2);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  });
  res.end(body);
}

function fail(res, status, message) {
  send(res, status, { message });
}

async function readBody(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  if (!chunks.length) return {};
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    return null; // признак некорректного JSON
  }
}

function currentUser(req) {
  const header = req.headers['authorization'] || '';
  if (!header.startsWith('Bearer ')) return null;
  const payload = verify(header.slice(7));
  if (!payload || payload.type !== 'access') return null;
  return db.users.find((u) => u.id === payload.sub && !u.deletedAt) || null;
}

const ROLE_LEVEL = { reader: 1, librarian: 2, admin: 3 };

function requireRole(res, user, minRole) {
  if (!user) {
    fail(res, 401, 'Требуется аутентификация');
    return false;
  }
  if (ROLE_LEVEL[user.role] < ROLE_LEVEL[minRole]) {
    fail(res, 403, `Операция доступна начиная с роли «${minRole}»`);
    return false;
  }
  return true;
}

const COLLECTIONS = ['books', 'authors', 'genres', 'publishers', 'readers', 'loans'];

// ─────────────────────────────── маршруты ───────────────────────────────

async function handle(req, res, url) {
  const q = Object.fromEntries(url.searchParams.entries());
  const path = url.pathname.replace(/\/+$/, '') || '/';
  const method = req.method.toUpperCase();
  const user = currentUser(req);

  // Учебные переключатели поведения
  if (q.__fail) {
    return fail(res, Number(q.__fail), 'Ошибка вызвана намеренно параметром __fail');
  }

  // ── служебные ──
  if (path === '/api/__reset' && method === 'POST') {
    seed();
    return send(res, 200, { message: 'Данные восстановлены в исходное состояние' });
  }

  if (path === '/api/__health' && method === 'GET') {
    return send(res, 200, { status: 'ok', time: new Date().toISOString() });
  }

  // ── аутентификация ──
  if (path === '/api/auth/register' && method === 'POST') {
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

    const errors = {};
    const username = String(body.username || '').trim();
    const password = String(body.password || '');
    if (username.length < 3) errors.username = 'Логин не короче трёх символов';
    else if (db.users.find((u) => u.username === username)) errors.username = 'Такой логин уже занят';
    if (password.length < 8) errors.password = 'Пароль не короче восьми символов';
    else if (!/\d/.test(password)) errors.password = 'Пароль должен содержать цифру';
    else if (!/[^\p{L}\d\s]/u.test(password)) errors.password = 'Пароль должен содержать специальный символ'; // ПР5
    if (body.email && !/^[\w.+-]+@[\w-]+\.[\w.-]+$/.test(String(body.email)))
      errors.email = 'Некорректный адрес почты';

    if (Object.keys(errors).length) {
      return send(res, 422, { message: 'Ошибка валидации', errors });
    }

    const id = push('users', {
      username,
      passwordHash: hash(password),
      fullName: String(body.fullName || username),
      email: String(body.email || ''),
      role: 'reader',
      readerId: null,
    });
    return send(res, 201, expandUser(db.users.find((u) => u.id === id)));
  }

  if (path === '/api/auth/login' && method === 'POST') {
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

    const found = db.users.find(
      (u) => u.username === String(body.username || '').trim() && !u.deletedAt
    );
    if (!found || found.passwordHash !== hash(String(body.password || ''))) {
      return fail(res, 401, 'Неверный логин или пароль');
    }

    const now = Math.floor(Date.now() / 1000);
    const accessToken = sign({ sub: found.id, role: found.role, type: 'access', exp: now + ACCESS_TTL });
    const refreshToken = sign({ sub: found.id, type: 'refresh', exp: now + REFRESH_TTL });
    db.refreshTokens.add(refreshToken);

    return send(res, 200, {
      accessToken,
      refreshToken,
      expiresIn: ACCESS_TTL,
      user: expandUser(found),
    });
  }

  if (path === '/api/auth/refresh' && method === 'POST') {
    const body = await readBody(req);
    const token = body && body.refreshToken;
    const payload = verify(token);
    if (!payload || payload.type !== 'refresh' || !db.refreshTokens.has(token)) {
      return fail(res, 401, 'Токен обновления недействителен');
    }
    const found = db.users.find((u) => u.id === payload.sub);
    if (!found) return fail(res, 401, 'Пользователь не найден');

    db.refreshTokens.delete(token);
    const now = Math.floor(Date.now() / 1000);
    const accessToken = sign({ sub: found.id, role: found.role, type: 'access', exp: now + ACCESS_TTL });
    const refreshToken = sign({ sub: found.id, type: 'refresh', exp: now + REFRESH_TTL });
    db.refreshTokens.add(refreshToken);

    return send(res, 200, { accessToken, refreshToken, expiresIn: ACCESS_TTL, user: expandUser(found) });
  }

  if (path === '/api/auth/me' && method === 'GET') {
    if (!user) return fail(res, 401, 'Требуется аутентификация');
    return send(res, 200, expandUser(user));
  }

  if (path === '/api/auth/logout' && method === 'POST') {
    const body = await readBody(req);
    if (body && body.refreshToken) db.refreshTokens.delete(body.refreshToken);
    return send(res, 204);
  }

  // ── управление пользователями (только admin) ──
  if (path === '/api/users' && method === 'GET') {
    if (!requireRole(res, user, 'admin')) return;
    const rows = applySort(db.users.filter((u) => !u.deletedAt), q.sort);
    const page = paginate(rows, q);
    return send(res, 200, { ...page, items: page.items.map(expandUser) });
  }

  // ── специальные операции с выдачами ──
  if (path === '/api/loans' && method === 'POST') {
    if (!requireRole(res, user, 'librarian')) return;
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

    const errors = {};
    const reader = db.readers.find((r) => r.id === Number(body.readerId) && !r.deletedAt);
    const book = db.books.find((b) => b.id === Number(body.bookId) && !b.deletedAt);
    if (!reader) errors.readerId = 'Читатель не найден';
    if (!book) errors.bookId = 'Книга не найдена';
    const days = Number(body.days || 14);
    if (!Number.isInteger(days) || days < 1 || days > 90) errors.days = 'Срок от 1 до 90 дней';
    if (Object.keys(errors).length) return send(res, 422, { message: 'Ошибка валидации', errors });

    if (book.copiesAvailable < 1) {
      return fail(res, 409, 'Нет свободных экземпляров этой книги');
    }

    const issuedAt = new Date();
    const dueAt = new Date(issuedAt.getTime() + days * 86400000);
    const id = push('loans', {
      readerId: reader.id,
      bookId: book.id,
      issuedAt: issuedAt.toISOString(),
      dueAt: dueAt.toISOString(),
      returnedAt: null,
    });
    book.copiesAvailable -= 1;
    return send(res, 201, expandLoan(db.loans.find((l) => l.id === id)));
  }

  let m = path.match(/^\/api\/loans\/(\d+)\/return$/);
  if (m && method === 'POST') {
    if (!requireRole(res, user, 'librarian')) return;
    const loan = db.loans.find((l) => l.id === Number(m[1]) && !l.deletedAt);
    if (!loan) return fail(res, 404, 'Выдача не найдена');
    if (loan.returnedAt) return fail(res, 409, 'Выдача уже закрыта');

    loan.returnedAt = new Date().toISOString();
    const book = db.books.find((b) => b.id === loan.bookId);
    if (book) book.copiesAvailable = Math.min(book.copiesTotal, book.copiesAvailable + 1);
    return send(res, 200, expandLoan(loan));
  }

  // ── ПР5: чтение и запись ресурсов только с действующим токеном ──
  if (/^\/api\/(books|authors|genres|publishers|readers|loans)(\/|$)/.test(path) && !user) {
    return fail(res, 401, 'Требуется аутентификация');
  }

  // ── ПР5: смена роли пользователя (только admin) ──
  const roleMatch = path.match(/^\/api\/users\/(\d+)$/);
  if (roleMatch && method === 'PATCH') {
    if (!requireRole(res, user, 'admin')) return;
    const target = db.users.find((u) => u.id === Number(roleMatch[1]) && !u.deletedAt);
    if (!target) return fail(res, 404, 'Пользователь не найден');
    const body = await readBody(req);
    if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');
    if (!ROLE_LEVEL[body.role]) {
      return send(res, 422, { message: 'Ошибка валидации', errors: { role: 'Допустимые роли: reader, librarian, admin' } });
    }
    if (target.id === user.id) return fail(res, 409, 'Нельзя изменить собственную роль');
    target.role = body.role;
    return send(res, 200, expandUser(target));
  }

  // ── ПР5: продление выдачи ──
  const extendMatch = path.match(/^\/api\/loans\/(\d+)\/extend$/);
  if (extendMatch && method === 'POST') {
    if (!requireRole(res, user, 'reader')) return;
    const loan = db.loans.find((l) => l.id === Number(extendMatch[1]) && !l.deletedAt);
    if (!loan) return fail(res, 404, 'Выдача не найдена');
    if (user.role === 'reader' && loan.readerId !== user.readerId) {
      return fail(res, 403, 'Продлевать можно только собственные выдачи');
    }
    if (loan.returnedAt) return fail(res, 409, 'Выдача уже закрыта');
    if (new Date(loan.dueAt) < new Date()) return fail(res, 409, 'Просроченную выдачу продлить нельзя: верните книгу');
    if ((loan.extensions || 0) >= 2) return fail(res, 409, 'Выдачу можно продлить не более двух раз');
    loan.dueAt = new Date(new Date(loan.dueAt).getTime() + 7 * 86400000).toISOString();
    loan.extensions = (loan.extensions || 0) + 1;
    return send(res, 200, expandLoan(loan));
  }

  // ── единообразный CRUD ──
  m = path.match(/^\/api\/([a-z]+)(?:\/(\d+))?(?:\/(restore))?$/);
  const bulk = path.match(/^\/api\/([a-z]+)\/bulk-delete$/);

  if (bulk && method === 'POST') {
    const collection = bulk[1];
    if (!COLLECTIONS.includes(collection)) return fail(res, 404, 'Ресурс не найден');
    if (!requireRole(res, user, 'librarian')) return;

    const body = await readBody(req);
    const ids = Array.isArray(body && body.ids) ? body.ids.map(Number) : [];
    if (!ids.length) return send(res, 422, { message: 'Ошибка валидации', errors: { ids: 'Передайте непустой список идентификаторов' } });

    let deleted = 0;
    for (const row of db[collection]) {
      if (ids.includes(row.id) && !row.deletedAt) {
        row.deletedAt = new Date().toISOString();
        deleted += 1;
      }
    }
    return send(res, 200, { deleted });
  }

  if (m) {
    const collection = m[1];
    const id = m[2] ? Number(m[2]) : null;
    const action = m[3] || null;

    if (!COLLECTIONS.includes(collection)) return fail(res, 404, 'Ресурс не найден');
    const expand = EXPANDERS[collection];

    // восстановление
    if (action === 'restore' && method === 'POST') {
      if (!requireRole(res, user, 'admin')) return;
      const row = db[collection].find((x) => x.id === id);
      if (!row) return fail(res, 404, 'Объект не найден');
      row.deletedAt = null;
      return send(res, 200, expand(row));
    }

    // список
    if (id === null && method === 'GET') {
      let rows = db[collection];
      if (q.includeDeleted !== 'true') rows = rows.filter((x) => !x.deletedAt);

      // читатель видит только свои выдачи
      if (collection === 'loans' && user && user.role === 'reader') {
        rows = rows.filter((l) => l.readerId === user.readerId);
      }
      // ПР5: читатель видит в списке читателей только себя
      if (collection === 'readers' && user && user.role === 'reader') {
        rows = rows.filter((r) => r.id === user.readerId);
      }

      rows = applyFilters(collection, rows, q);
      rows = applySort(rows, q.sort);
      const page = paginate(rows, q);
      return send(res, 200, { ...page, items: page.items.map(expand) });
    }

    // одна запись
    if (id !== null && method === 'GET') {
      if (collection === 'loans' && user.role === 'reader') {
        const own = db.loans.find((l) => l.id === id);
        if (own && own.readerId !== user.readerId) return fail(res, 403, 'Читатель может смотреть только собственные выдачи'); // ПР5
      }
      if (collection === 'readers' && user.role === 'reader' && id !== user.readerId) {
        return fail(res, 403, 'Читатель может смотреть только собственную карточку'); // ПР5
      }
      const row = db[collection].find((x) => x.id === id && (q.includeDeleted === 'true' || !x.deletedAt));
      if (!row) return fail(res, 404, 'Объект не найден');
      return send(res, 200, expand(row));
    }

    // создание
    if (id === null && method === 'POST') {
      if (!requireRole(res, user, 'librarian')) return;
      const body = await readBody(req);
      if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

      const errors = validate(collection, body);
      if (Object.keys(errors).length) return send(res, 422, { message: 'Ошибка валидации', errors });

      const data = normalize(collection, body);
      const newId = push(collection, data);
      const row = db[collection].find((x) => x.id === newId);
      if (collection === 'books') row.copiesAvailable = row.copiesTotal;
      return send(res, 201, expand(row));
    }

    // изменение
    if (id !== null && (method === 'PUT' || method === 'PATCH')) {
      if (!requireRole(res, user, 'librarian')) return;
      const row = db[collection].find((x) => x.id === id && !x.deletedAt);
      if (!row) return fail(res, 404, 'Объект не найден');

      const body = await readBody(req);
      if (!body) return fail(res, 400, 'Тело запроса не является корректным JSON');

      const merged = method === 'PATCH' ? { ...row, ...body } : body;
      const errors = validate(collection, merged, id);
      if (Object.keys(errors).length) return send(res, 422, { message: 'Ошибка валидации', errors });

      Object.assign(row, normalize(collection, merged));
      if (collection === 'books') {
        const inUse = db.loans.filter((l) => l.bookId === id && !l.returnedAt && !l.deletedAt).length;
        row.copiesAvailable = Math.max(0, row.copiesTotal - inUse);
      }
      return send(res, 200, expand(row));
    }

    // удаление
    if (id !== null && method === 'DELETE') {
      const hard = q.hard === 'true';
      if (!requireRole(res, user, hard ? 'admin' : 'librarian')) return;

      const index = db[collection].findIndex((x) => x.id === id);
      if (index === -1) return fail(res, 404, 'Объект не найден');

      if (hard) {
        if (collection === 'books') {
          const active = db.loans.some((l) => l.bookId === id && !l.returnedAt && !l.deletedAt);
          if (active) return fail(res, 409, 'Книга выдана и не может быть удалена физически');
        }
        if (collection === 'readers') {
          const active = db.loans.some((l) => l.readerId === id && !l.returnedAt && !l.deletedAt);
          if (active) return fail(res, 409, 'У читателя есть незакрытые выдачи');
        }
        db[collection].splice(index, 1);
      } else {
        db[collection][index].deletedAt = new Date().toISOString();
      }
      return send(res, 204);
    }
  }

  return fail(res, 404, `Адрес ${method} ${path} не обслуживается`);
}

function normalize(collection, body) {
  const num = (v) => (v == null || v === '' ? null : Number(v));
  const str = (v) => (v == null ? '' : String(v).trim());
  const ids = (v) => (Array.isArray(v) ? v.map(Number).filter((n) => Number.isInteger(n)) : []);

  switch (collection) {
    case 'books':
      return {
        title: str(body.title),
        isbn: str(body.isbn),
        year: num(body.year),
        pages: num(body.pages),
        publisherId: num(body.publisherId),
        authorIds: ids(body.authorIds),
        genreIds: ids(body.genreIds),
        copiesTotal: num(body.copiesTotal) ?? 0,
      };
    case 'authors':
      return { fullName: str(body.fullName), birthYear: num(body.birthYear), country: str(body.country) };
    case 'genres':
      return { name: str(body.name), description: str(body.description) };
    case 'publishers':
      return { name: str(body.name), city: str(body.city), foundedYear: num(body.foundedYear) };
    case 'readers':
      return { fullName: str(body.fullName), email: str(body.email), phone: str(body.phone) };
    default:
      return { ...body };
  }
}

// ─────────────────────────────── запуск ───────────────────────────────

seed();

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  // Предварительный запрос браузера. Без этого обработчика
  // на web не заработает ни один запрос с заголовком Authorization.
  if (req.method === 'OPTIONS') {
    cors(res);
    res.writeHead(204);
    return res.end();
  }

  const delay = Number(url.searchParams.get('__delay') || 0);
  if (delay > 0) await new Promise((r) => setTimeout(r, Math.min(delay, 10000)));

  const started = Date.now();
  try {
    await handle(req, res, url);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) fail(res, 500, 'Внутренняя ошибка сервера: ' + err.message);
  }
  console.log(
    `${req.method.padEnd(6)} ${url.pathname}${url.search}  → ${res.statusCode}  ${Date.now() - started} мс`
  );
});

server.listen(PORT, () => {
  console.log('');
  console.log('  Учебное API «Библиотека»');
  console.log(`  Адрес:              http://localhost:${PORT}/api`);
  console.log(`  Разрешённый источник: ${ORIGIN}`);
  console.log(`  Срок жизни токена:  ${ACCESS_TTL} с`);
  console.log('');
  console.log('  Учётные записи:  admin/admin123   librarian/librarian123   reader/reader123');
  console.log('  Сброс данных:    POST /api/__reset');
  console.log('  Задержка ответа: любой запрос с ?__delay=1500');
  console.log('  Ошибка по требованию: любой запрос с ?__fail=500');
  console.log('');
});
