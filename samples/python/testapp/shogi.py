# 将棋 - コンピュータ対戦（MicroPython 版）
# S:/testapp/shogi.rb の移植（2026-10-30）。テキスト面 80x28、低レゾは使わない。
BLACK = 1
WHITE = -1

PAWN = 1
LANCE = 2
KNIGHT = 3
SILVER = 4
GOLD = 5
BISHOP = 6
ROOK = 7
KING = 8

PROMOTE = (0, 9, 10, 11, 12, 0, 14, 15, 0)
PIECE_CHARS = ("", "P", "L", "N", "S", "G", "B", "R", "K")
DISPLAY_CHARS = ("", "歩", "香", "桂", "銀", "金", "角", "飛", "玉")
PROMOTED_CHARS = ("", "と", "杏", "圭", "全", "", "馬", "龍", "")
WHITE_KING_CHAR = "王"
VALUES = (0, 100, 300, 350, 450, 550, 800, 1000, 0,
          550, 550, 550, 550, 550, 1000, 1200)
HAND_VALUES = (0, 110, 320, 380, 480, 580, 850, 1050)

PROMOTE_FLAG = 100000
DROP_FLAG = 200000
MATE_SCORE = 1000000
INFINITY = 2000000
DEFAULT_TIME_MS = 2500
DEFAULT_MAX_DEPTH = 4

KING_DIRS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))
GOLD_DIRS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, 0))
SILVER_DIRS = ((-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 1))
KNIGHT_DIRS = ((-2, -1), (-2, 1))
BISHOP_DIRS = ((-1, -1), (-1, 1), (1, -1), (1, 1))
ROOK_DIRS = ((-1, 0), (1, 0), (0, -1), (0, 1))

def square_name(index):
    return str(9 - index % 9) + chr(97 + index // 9)

def move_to_usi(mv):
    if mv >= DROP_FLAG:
        rest = mv - DROP_FLAG
        typ = rest // 100
        to = rest % 100
        return PIECE_CHARS[typ] + "*" + square_name(to)
    promote = mv >= PROMOTE_FLAG
    base = mv - PROMOTE_FLAG if promote else mv
    frm = base // 81
    to = base % 81
    return square_name(frm) + square_name(to) + ("+" if promote else "")

def parse_square(s, index):
    if index + 1 >= len(s):
        return None
    f = ord(s[index])
    r = ord(s[index + 1])
    if f < 49 or f > 57:
        return None
    if 65 <= r <= 90:
        r -= 32
    if r < 97 or r > 105:
        return None
    col = 57 - f
    row = r - 97
    return row * 9 + col

def piece_type_from_byte(b):
    if 97 <= b <= 122:
        b -= 32
    if b == 80:
        return PAWN
    if b == 76:
        return LANCE
    if b == 78:
        return KNIGHT
    if b == 83:
        return SILVER
    if b == 71:
        return GOLD
    if b == 66:
        return BISHOP
    if b == 82:
        return ROOK
    return 0

def parse_move(line, legal):
    s = line.strip()
    if len(s) < 4:
        return []
    if ord(s[1]) == 42:
        if len(s) != 4:
            return []
        typ = piece_type_from_byte(ord(s[0]))
        if typ == 0:
            return []
        to = parse_square(s, 2)
        if to is None:
            return []
        mv = DROP_FLAG + typ * 100 + to
        return [mv] if mv in legal else []
    if len(s) != 4 and not (len(s) == 5 and ord(s[4]) == 43):
        return []
    frm = parse_square(s, 0)
    to = parse_square(s, 2)
    if frm is None or to is None:
        return []
    base = frm * 81 + to
    promote_char = ord(s[4]) if len(s) > 4 else 0
    unpromoted = None
    promoted = None
    for mv in legal:
        if mv >= DROP_FLAG:
            continue
        if mv >= PROMOTE_FLAG:
            if mv - PROMOTE_FLAG == base:
                promoted = mv
        elif mv == base:
            unpromoted = mv
    if promote_char == 43:
        return [promoted] if promoted is not None else []
    result = []
    if unpromoted is not None:
        result.append(unpromoted)
    if promoted is not None:
        result.append(promoted)
    return result

class Position:
    def __init__(self):
        self.board = [0] * 81
        self.hand_b = [0] * 8
        self.hand_w = [0] * 8
        self.turn = BLACK
        self.move_number = 1
        self.setup()

    def setup(self):
        back = (LANCE, KNIGHT, SILVER, GOLD, KING, GOLD, SILVER, KNIGHT, LANCE)
        for c in range(9):
            self.board[c] = -back[c]
            self.board[72 + c] = back[c]
        self.board[10] = -ROOK
        self.board[16] = -BISHOP
        self.board[64] = BISHOP
        self.board[70] = ROOK
        for c in range(9):
            self.board[18 + c] = -PAWN
            self.board[54 + c] = PAWN
        self.king_b = 76
        self.king_w = 4

    def hand(self, side):
        return self.hand_b if side == BLACK else self.hand_w

    def base_type(self, code):
        return code - 8 if code > 8 else code

    def king_square(self, side):
        return self.king_b if side == BLACK else self.king_w

    def in_check(self, side):
        k = self.king_square(side)
        if k is None:
            return True
        return self.attacked(k, -side)

    def attacked(self, square, by_side):
        for frm in range(81):
            p = self.board[frm]
            if p == 0:
                continue
            if (BLACK if p > 0 else WHITE) != by_side:
                continue
            if self.attacks(frm, square, p):
                return True
        return False

    def attacks(self, frm, to, piece):
        code = piece if piece > 0 else -piece
        typ = self.base_type(code)
        fr = frm // 9
        fc = frm % 9
        tr = to // 9
        tc = to % 9
        dr = tr - fr
        dc = tc - fc
        if dr == 0 and dc == 0:
            return False
        fwd = -1 if piece > 0 else 1
        if code == KING:
            return abs(dr) <= 1 and abs(dc) <= 1
        if code == 14:
            if abs(dr) == abs(dc):
                return self.clear_path(frm, to, dr, dc)
            return abs(dr) + abs(dc) == 1
        if code == 15:
            if dr == 0 or dc == 0:
                return self.clear_path(frm, to, dr, dc)
            return abs(dr) == 1 and abs(dc) == 1
        if code > 8:
            return self.gold_attack(dr, dc, fwd)
        if typ == PAWN:
            return dr == fwd and dc == 0
        if typ == LANCE:
            if not (dc == 0 and dr * fwd > 0):
                return False
            return self.clear_path(frm, to, dr, dc)
        if typ == KNIGHT:
            return dr == 2 * fwd and abs(dc) == 1
        if typ == SILVER:
            return (dr == fwd and abs(dc) <= 1) or (dr == -fwd and abs(dc) == 1)
        if typ == GOLD:
            return self.gold_attack(dr, dc, fwd)
        if typ == BISHOP:
            return abs(dr) == abs(dc) and self.clear_path(frm, to, dr, dc)
        if typ == ROOK:
            return (dr == 0 or dc == 0) and self.clear_path(frm, to, dr, dc)
        return False

    def gold_attack(self, dr, dc, fwd):
        return ((dr == fwd and abs(dc) <= 1) or (dr == 0 and abs(dc) == 1)
                or (dr == -fwd and dc == 0))

    def clear_path(self, frm, to, dr, dc):
        sr = 1 if dr > 0 else (-1 if dr < 0 else 0)
        sc = 1 if dc > 0 else (-1 if dc < 0 else 0)
        r = frm // 9 + sr
        c = frm % 9 + sc
        tr = to // 9
        tc = to % 9
        while r != tr or c != tc:
            if self.board[r * 9 + c] != 0:
                return False
            r += sr
            c += sc
        return True

    def pseudo_moves(self, side=None, include_drops=True):
        if side is None:
            side = self.turn
        moves = []
        for frm in range(81):
            p = self.board[frm]
            if p == 0:
                continue
            if (BLACK if p > 0 else WHITE) != side:
                continue
            code = p if p > 0 else -p
            typ = self.base_type(code)
            r = frm // 9
            c = frm % 9
            if code == KING:
                for dr, dc in KING_DIRS:
                    self.add_step(moves, frm, r + dr, c + dc, side, code)
            elif code == 14:
                for dr, dc in BISHOP_DIRS:
                    self.add_slide(moves, frm, dr, dc, side, code)
                for dr, dc in ROOK_DIRS:
                    self.add_step(moves, frm, r + dr, c + dc, side, code)
            elif code == 15:
                for dr, dc in ROOK_DIRS:
                    self.add_slide(moves, frm, dr, dc, side, code)
                for dr, dc in BISHOP_DIRS:
                    self.add_step(moves, frm, r + dr, c + dc, side, code)
            elif code > 8 or typ == GOLD:
                for dr, dc in GOLD_DIRS:
                    self.add_step(moves, frm, r + dr * side, c + dc, side, code)
            elif typ == SILVER:
                for dr, dc in SILVER_DIRS:
                    self.add_step(moves, frm, r + dr * side, c + dc, side, code)
            elif typ == KNIGHT:
                for dr, dc in KNIGHT_DIRS:
                    self.add_step(moves, frm, r + dr * side, c + dc, side, code)
            elif typ == PAWN:
                self.add_step(moves, frm, r - side, c, side, code)
            elif typ == LANCE:
                self.add_slide(moves, frm, -side, 0, side, code)
            elif typ == BISHOP:
                for dr, dc in BISHOP_DIRS:
                    self.add_slide(moves, frm, dr, dc, side, code)
            elif typ == ROOK:
                for dr, dc in ROOK_DIRS:
                    self.add_slide(moves, frm, dr, dc, side, code)
        if include_drops:
            self.add_drop_moves(moves, side)
        return moves

    def add_step(self, moves, frm, nr, nc, side, code):
        if nr < 0 or nr > 8 or nc < 0 or nc > 8:
            return
        to = nr * 9 + nc
        q = self.board[to]
        if q != 0 and (BLACK if q > 0 else WHITE) == side:
            return
        self.add_move(moves, frm, to, side, code)

    def add_slide(self, moves, frm, dr, dc, side, code):
        r = frm // 9 + dr
        c = frm % 9 + dc
        while 0 <= r <= 8 and 0 <= c <= 8:
            to = r * 9 + c
            q = self.board[to]
            if q == 0:
                self.add_move(moves, frm, to, side, code)
            else:
                if (BLACK if q > 0 else WHITE) != side:
                    self.add_move(moves, frm, to, side, code)
                break
            r += dr
            c += dc

    def add_move(self, moves, frm, to, side, code):
        base = frm * 81 + to
        typ = self.base_type(code)
        if code <= 8 and PROMOTE[typ] != 0:
            fr = frm // 9
            tr = to // 9
            zone = (fr <= 2 or tr <= 2) if side == BLACK else (fr >= 6 or tr >= 6)
            if zone:
                if self.must_promote(typ, side, tr):
                    moves.append(base + PROMOTE_FLAG)
                else:
                    moves.append(base)
                    moves.append(base + PROMOTE_FLAG)
                return
        moves.append(base)

    def must_promote(self, typ, side, row):
        if typ == PAWN or typ == LANCE:
            return row == (0 if side == BLACK else 8)
        if typ == KNIGHT:
            return row <= 1 if side == BLACK else row >= 7
        return False

    def add_drop_moves(self, moves, side):
        hand = self.hand_b if side == BLACK else self.hand_w
        nifu = None
        if hand[PAWN] > 0:
            nifu = [False] * 9
            for c in range(9):
                for r in range(9):
                    if self.board[r * 9 + c] == side * PAWN:
                        nifu[c] = True
        for typ in range(1, 8):
            if hand[typ] <= 0:
                continue
            for to in range(81):
                if self.board[to] != 0:
                    continue
                r = to // 9
                c = to % 9
                if typ == PAWN:
                    if (r == 0 if side == BLACK else r == 8):
                        continue
                    if nifu[c]:
                        continue
                elif typ == LANCE:
                    if (r == 0 if side == BLACK else r == 8):
                        continue
                elif typ == KNIGHT:
                    if (r <= 1 if side == BLACK else r >= 7):
                        continue
                moves.append(DROP_FLAG + typ * 100 + to)

    def legal_moves(self, side=None, check_drop_mate=True):
        if side is None:
            side = self.turn
        old_turn = self.turn
        self.turn = side
        result = []
        for mv in self.pseudo_moves(side):
            u = self.do_move(mv)
            legal = not self.in_check(side)
            if legal and check_drop_mate and mv >= DROP_FLAG:
                rest = mv - DROP_FLAG
                if rest // 100 == PAWN and self.in_check(self.turn):
                    if not self.legal_moves(self.turn, False):
                        legal = False
            self.undo_move(u)
            if legal:
                result.append(mv)
        self.turn = old_turn
        return result

    def do_move(self, mv):
        side = self.turn
        hand = self.hand_b if side == BLACK else self.hand_w
        if mv >= DROP_FLAG:
            rest = mv - DROP_FLAG
            typ = rest // 100
            to = rest % 100
            self.board[to] = side * typ
            hand[typ] -= 1
            undo = (mv, 0)
        else:
            promote = mv >= PROMOTE_FLAG
            base = mv - PROMOTE_FLAG if promote else mv
            frm = base // 81
            to = base % 81
            p = self.board[frm]
            code = p if p > 0 else -p
            captured = self.board[to]
            if captured != 0:
                ctype = captured if captured > 0 else -captured
                if ctype != KING:
                    hand[self.base_type(ctype)] += 1
            if promote:
                self.board[to] = PROMOTE[code] * side
            else:
                self.board[to] = p
            self.board[frm] = 0
            if code == KING:
                if side == BLACK:
                    self.king_b = to
                else:
                    self.king_w = to
            undo = (mv, captured)
        self.turn = -side
        return undo

    def undo_move(self, undo):
        mv, captured = undo
        self.turn = -self.turn
        side = self.turn
        hand = self.hand_b if side == BLACK else self.hand_w
        if mv >= DROP_FLAG:
            rest = mv - DROP_FLAG
            typ = rest // 100
            to = rest % 100
            self.board[to] = 0
            hand[typ] += 1
        else:
            promote = mv >= PROMOTE_FLAG
            base = mv - PROMOTE_FLAG if promote else mv
            frm = base // 81
            to = base % 81
            p = self.board[to]
            code = p if p > 0 else -p
            orig = code - 8 if promote else code
            self.board[frm] = orig * side
            self.board[to] = captured
            if captured != 0:
                ctype = captured if captured > 0 else -captured
                if ctype != KING:
                    hand[self.base_type(ctype)] -= 1
            if orig == KING:
                if side == BLACK:
                    self.king_b = frm
                else:
                    self.king_w = frm

    def signature(self):
        return (",".join(str(x) for x in self.board) + "|"
                + ",".join(str(x) for x in self.hand_b) + "|"
                + ",".join(str(x) for x in self.hand_w) + "|" + str(self.turn))

class SearchTimeout(Exception):
    pass

class Engine:
    def __init__(self, limit_ms=DEFAULT_TIME_MS, max_depth=DEFAULT_MAX_DEPTH):
        self.limit_ms = limit_ms
        self.max_depth = max_depth
        self.nodes = 0
        self.depth = 0
        self.score = 0
        self.history = [0] * (81 * 81)
        self.killer1 = [0] * 128
        self.killer2 = [0] * 128

    def choose_move(self, pos):
        self.pos = pos
        self.deadline = M.ms() + self.limit_ms
        self.nodes = 0
        self.depth = 0
        self.score = 0
        root_moves = pos.legal_moves()
        if not root_moves:
            return None
        best = root_moves[0]
        root_moves = self.order_moves(root_moves, best, 0)
        try:
            s, mv = self.root_search(root_moves, 1, False)
            best = mv
            self.score = s
            self.depth = 1
        except SearchTimeout:
            pass
        if M.ms() < self.deadline:
            root_moves = self.order_moves(root_moves, best, 0)
            try:
                s, mv = self.root_search(root_moves, 1, True)
                best = mv
                self.score = s
            except SearchTimeout:
                pass
        d = 2
        while d <= self.max_depth:
            if M.ms() >= self.deadline:
                break
            root_moves = self.order_moves(root_moves, best, 0)
            try:
                s, mv = self.root_search(root_moves, d, True)
            except SearchTimeout:
                break
            best = mv
            self.score = s
            self.depth = d
            if abs(s) > MATE_SCORE - 1000:
                break
            d += 1
        return best

    def root_search(self, moves, depth, use_q):
        alpha = -INFINITY
        beta = INFINITY
        best_score = -INFINITY
        best_move = moves[0]
        for mv in moves:
            if M.ms() >= self.deadline:
                raise SearchTimeout()
            u = self.pos.do_move(mv)
            try:
                if depth <= 1 and not use_q:
                    val = -self.evaluate()
                else:
                    val = -self.negamax(depth - 1, -beta, -alpha, 1, use_q)
            finally:
                self.pos.undo_move(u)
            if val > best_score:
                best_score = val
                best_move = mv
            if best_score > alpha:
                alpha = best_score
        return best_score, best_move

    def negamax(self, depth, alpha, beta, ply, use_q=True):
        self.nodes += 1
        if (self.nodes & 7) == 0 and M.ms() >= self.deadline:
            raise SearchTimeout()
        if depth <= 0:
            return self.quiesce(alpha, beta, ply, 0) if use_q else self.evaluate()
        moves = self.pos.pseudo_moves()
        moves = self.order_moves(moves, 0, ply)
        best = -INFINITY
        legal_count = 0
        for mv in moves:
            u = self.pos.do_move(mv)
            mover = -self.pos.turn
            if self.pos.in_check(mover):
                self.pos.undo_move(u)
                continue
            legal_count += 1
            try:
                val = -self.negamax(depth - 1, -beta, -alpha, ply + 1, use_q)
            finally:
                self.pos.undo_move(u)
            if val > best:
                best = val
            if best > alpha:
                alpha = best
            if alpha >= beta:
                if mv < DROP_FLAG and ply < 128:
                    base = mv - PROMOTE_FLAG if mv >= PROMOTE_FLAG else mv
                    frm = base // 81
                    to = base % 81
                    self.history[frm * 81 + to] += depth * depth
                    if self.killer1[ply] != mv:
                        self.killer2[ply] = self.killer1[ply]
                        self.killer1[ply] = mv
                break
        if legal_count == 0:
            return -MATE_SCORE + ply
        return best

    def quiesce(self, alpha, beta, ply, qdepth):
        self.nodes += 1
        if (self.nodes & 7) == 0 and M.ms() >= self.deadline:
            raise SearchTimeout()
        in_check = self.pos.in_check(self.pos.turn)
        if not in_check:
            stand = self.evaluate()
            if stand >= beta:
                return stand
            if stand > alpha:
                alpha = stand
        if qdepth >= 4:
            return self.evaluate()
        moves = self.pos.pseudo_moves() if in_check else self.capture_moves()
        moves = self.order_moves(moves, 0, ply)
        best = -INFINITY if in_check else alpha
        legal_count = 0
        for mv in moves:
            u = self.pos.do_move(mv)
            mover = -self.pos.turn
            if self.pos.in_check(mover):
                self.pos.undo_move(u)
                continue
            legal_count += 1
            try:
                val = -self.quiesce(-beta, -best, ply + 1, qdepth + 1)
            finally:
                self.pos.undo_move(u)
            if val > best:
                best = val
            if best >= beta:
                return best
        if in_check and legal_count == 0:
            return -MATE_SCORE + ply
        return best

    def capture_moves(self):
        result = []
        for mv in self.pos.pseudo_moves(self.pos.turn, False):
            if mv >= DROP_FLAG:
                continue
            base = mv - PROMOTE_FLAG if mv >= PROMOTE_FLAG else mv
            to = base % 81
            if self.pos.board[to] != 0 or mv >= PROMOTE_FLAG:
                result.append(mv)
        return result

    def order_moves(self, moves, first, ply):
        k1 = self.killer1[ply] if ply < 128 else 0
        k2 = self.killer2[ply] if ply < 128 else 0
        def key(mv):
            if mv == first:
                s = 100000000
            elif mv >= DROP_FLAG:
                s = 0
            else:
                base = mv - PROMOTE_FLAG if mv >= PROMOTE_FLAG else mv
                frm = base // 81
                to = base % 81
                victim = self.pos.board[to]
                if victim != 0:
                    attacker = self.pos.board[frm]
                    attacker = attacker if attacker > 0 else -attacker
                    v = victim if victim > 0 else -victim
                    s = 100000 + VALUES[v] * 10 - VALUES[attacker]
                elif mv >= PROMOTE_FLAG:
                    s = 50000
                elif mv == k1:
                    s = 40000
                elif mv == k2:
                    s = 39000
                else:
                    s = self.history[frm * 81 + to]
            return -s
        return sorted(moves, key=key)

    def evaluate(self):
        score = 0
        board = self.pos.board
        for i in range(81):
            p = board[i]
            if p == 0:
                continue
            side = BLACK if p > 0 else WHITE
            code = p if p > 0 else -p
            v = VALUES[code]
            r = i // 9
            c = i % 9
            if code == PAWN:
                v += ((6 - r) if side == BLACK else (r - 2)) * 6
            elif code == LANCE:
                v += ((6 - r) if side == BLACK else (r - 2)) * 3
            elif code == KNIGHT:
                v += ((6 - r) if side == BLACK else (r - 2)) * 4
            elif code == SILVER:
                v += ((6 - r) if side == BLACK else (r - 2)) * 3
            elif code == BISHOP or code == ROOK:
                v += (4 - (abs(r - 4) + abs(c - 4))) * 2
            elif code == KING:
                home = r >= 7 if side == BLACK else r <= 1
                if home:
                    v += 30
            score += v * side
        hb = self.pos.hand(BLACK)
        hw = self.pos.hand(WHITE)
        for t in range(1, 8):
            score += hb[t] * HAND_VALUES[t]
            score -= hw[t] * HAND_VALUES[t]
        return score if self.pos.turn == BLACK else -score

class Game:
    BOARD_X = 23
    BOARD_Y = 3
    KEY_ENTER = 13
    KEY_TAB = 9
    KEY_SPACE = 32
    KEY_UP = 0x90
    KEY_DOWN = 0x91
    KEY_LEFT = 0x92
    KEY_RIGHT = 0x93
    KEY_PGUP = 0x94
    KEY_PGDN = 0x95

    def __init__(self, limit_ms=DEFAULT_TIME_MS):
        self.pos = Position()
        self.engine = Engine(limit_ms)
        self.human = BLACK
        self.last_move = None
        self.history = {}
        self.message = None
        self.message_color = None
        self.screen_ready = False
        self.side_choice = 0
        self.menu_focus = "board"
        self.command_index = 0
        self.hand_index = 0
        self.cursor_dr = 4
        self.cursor_dc = 4
        self.selected_from = None
        self.selected_drop = None
        self.promotion_moves = None
        self.promotion_index = 0
        self.board_active = False

    def run(self):
        self.banner()
        if not self.choose_side():
            return
        self.record_position()
        while True:
            legal = self.pos.legal_moves()
            if self.pos.turn == self.human:
                self.reset_menu(legal)
            self.show(legal)
            if not legal:
                self.show_result(legal)
                return
            if self.pos.turn == self.human:
                mv = self.human_move(legal)
                if mv is None:
                    return
            else:
                mv = self.ai_move(legal)
                if mv is None:
                    self.show_result(legal)
                    return
            self.pos.do_move(mv)
            self.last_move = mv
            self.pos.move_number += 1
            if self.repetition_draw():
                legal = self.pos.legal_moves()
                self.message = "千日手（同一局面4回）で引き分けです。"
                self.message_color = M.TEXT_BLUE
                self.show(legal)
                return

    def banner(self):
        M.text_clear(M.tattr(0, self.bg(), 0))
        M.set_text_attr(M.tattr(M.TEXT_BRIGHT_WHITE, self.bg(), 0))
        M.locate(0, 0)
        print("将棋 - コンピュータ対戦")
        print()
        print("盤面は横向きです。左があなた、右がAIです。")
        print("筋は上から下、段は左から右に並びます。")
        print("盤面では矢印でカーソルを動かし、Enter で駒を選びます。")
        print("もう一度 Enter で移動します。Tab でメニューに切り替わります。")
        print("先手(b)か後手(w)を選べます。")
        print()

    def choose_side(self):
        self.side_choice = 1 if self.human == WHITE else 0
        self.clear_keys()
        while True:
            self.draw_side_menu()
            key = self.read_key()
            if key is None:
                return False
            if key == self.KEY_LEFT:
                self.side_choice = 0
            elif key == self.KEY_RIGHT:
                self.side_choice = 1
            elif key == self.KEY_ENTER or key == self.KEY_SPACE:
                self.human = BLACK if self.side_choice == 0 else WHITE
                return True
            elif key == 98 or key == 66:
                self.human = BLACK
                return True
            elif key == 119 or key == 87:
                self.human = WHITE
                return True

    def draw_side_menu(self):
        self.clear_row(7)
        self.clear_row(8)
        self.clear_row(9)
        self.put_text(0, 7, "モードを選んでください", M.TEXT_BRIGHT_WHITE, M.TEXT_BOLD)
        if self.side_choice == 0:
            self.put_text(0, 8, "[ 先手（b） ]", M.TEXT_BLACK, M.TEXT_BOLD, M.TEXT_BRIGHT_BLUE)
            self.put_text(22, 8, "[ 後手（w） ]", M.TEXT_BRIGHT_WHITE)
        else:
            self.put_text(0, 8, "[ 先手（b） ]", M.TEXT_BRIGHT_WHITE)
            self.put_text(22, 8, "[ 後手（w） ]", M.TEXT_BLACK, M.TEXT_BOLD, M.TEXT_BRIGHT_BLUE)
        self.put_text(0, 9, "←→:選択  Enter:決定  b/w でも選べます", M.TEXT_BRIGHT_GREEN)

    def clear_keys(self):
        M.clear_keys()

    def read_key(self):
        return M.wait_key()

    def reset_menu(self, legal):
        self.menu_focus = "board"
        self.command_index = 0
        self.hand_index = 0
        self.selected_from = None
        self.selected_drop = None
        self.promotion_moves = None
        self.promotion_index = 0
        self.cursor_dr = 4
        self.cursor_dc = 4
        first = None
        for mv in legal:
            if mv < DROP_FLAG:
                base = mv - PROMOTE_FLAG if mv >= PROMOTE_FLAG else mv
                first = base // 81
                break
        if first is not None:
            self.cursor_dr, self.cursor_dc = self.display_of(first)

    def move_base(self, mv):
        return mv - PROMOTE_FLAG if mv >= PROMOTE_FLAG else mv

    def move_from(self, mv):
        if mv >= DROP_FLAG:
            return None
        return self.move_base(mv) // 81

    def move_to(self, mv):
        if mv >= DROP_FLAG:
            return (mv - DROP_FLAG) % 100
        return self.move_base(mv) % 81

    def drop_type(self, mv):
        return (mv - DROP_FLAG) // 100 if mv >= DROP_FLAG else None

    def drop_targets(self, legal, typ):
        return [self.move_to(mv) for mv in legal if self.drop_type(mv) == typ]

    def moves_from(self, legal, frm):
        return [mv for mv in legal if mv < DROP_FLAG and self.move_from(mv) == frm]

    def moves_between(self, legal, frm, to):
        return [mv for mv in legal if mv < DROP_FLAG and self.move_from(mv) == frm and self.move_to(mv) == to]

    def record_position(self):
        sig = self.pos.signature()
        self.history[sig] = self.history.get(sig, 0) + 1

    def repetition_draw(self):
        self.record_position()
        return self.history.get(self.pos.signature(), 0) >= 4

    def bg(self): return M.TEXT_BLACK
    def board_bg(self): return M.TEXT_BRIGHT_YELLOW
    def cursor_bg(self): return M.TEXT_BRIGHT_GREEN
    def target_bg(self): return M.TEXT_BRIGHT_CYAN
    def source_bg(self): return M.TEXT_BRIGHT_WHITE
    def human_move_bg(self): return M.TEXT_BRIGHT_BLUE
    def ai_move_bg(self): return M.TEXT_BRIGHT_RED
    def last_move_bg(self): return self.ai_move_bg() if self.pos.turn == self.human else self.human_move_bg()
    def grid_color(self): return M.TEXT_GREEN if self.board_active else M.TEXT_BLACK

    def board_cursor_mode(self, legal):
        return (self.pos.turn == self.human and bool(legal)
                and (self.menu_focus == "board" or self.menu_focus == "promotion"))

    def sync_board_mode(self, legal):
        self.board_active = self.board_cursor_mode(legal)

    def show(self, legal=None):
        if legal is None:
            legal = self.pos.legal_moves()
        if not self.screen_ready:
            M.text_clear(M.tattr(M.TEXT_BLACK, self.bg(), 0))
            self.screen_ready = True
        self.sync_board_mode(legal)
        self.clear_non_board()
        self.draw_header()
        self.draw_board(legal)
        self.draw_panels()
        self.draw_hint(legal)
        self.draw_message()
        M.locate(0, 26)

    def clear_non_board(self):
        self.clear_row(0)
        M.text_put(0, 1, " " * 19, M.tattr(M.TEXT_BLACK, self.bg(), 0))
        M.text_put(61, 1, " " * 19, M.tattr(M.TEXT_BLACK, self.bg(), 0))
        for y in range(2, 12):
            M.text_put(0, y, " " * 19, M.tattr(M.TEXT_BLACK, self.bg(), 0))
            M.text_put(61, y, " " * 19, M.tattr(M.TEXT_BLACK, self.bg(), 0))
        for y in range(21, 28):
            self.clear_row(y)

    def put_text(self, x, y, text, color, flags=0, bgcolor=None):
        M.text_put(x, y, text, M.tattr(color, self.bg() if bgcolor is None else bgcolor, flags))

    def board_text(self, x, y, text, color, flags=0):
        self.put_text(x, y, text, color, flags, self.board_bg())

    def clear_row(self, y):
        M.text_put(0, y, " " * 80, M.tattr(M.TEXT_BLACK, self.bg(), 0))

    def draw_header(self):
        self.put_text(0, 0, "将棋", M.TEXT_BRIGHT_YELLOW, M.TEXT_BOLD)
        self.put_text(6, 0, "コンピュータ対戦", M.TEXT_BRIGHT_WHITE)
        self.put_text(60, 0, self.turn_text(), M.TEXT_BRIGHT_WHITE, M.TEXT_BOLD)
        last = "-" if self.last_move is None else move_to_usi(self.last_move)
        self.put_text(0, 1, "直前の手: " + last, M.TEXT_BRIGHT_WHITE)
        if self.pos.in_check(self.pos.turn):
            self.put_text(48, 0, "王手！", M.TEXT_BRIGHT_RED, M.TEXT_BOLD)

    def board_cell_flags(self):
        return (M.TEXT_DW | M.TEXT_DH | 0x00800000 | 0x01000000 | 0x8000 | M.TEXT_UNDER)

    def draw_board(self, legal):
        ranks = ("i", "h", "g", "f", "e", "d", "c", "b", "a") if self.human == BLACK else ("a", "b", "c", "d", "e", "f", "g", "h", "i")
        files = ("9", "8", "7", "6", "5", "4", "3", "2", "1") if self.human == BLACK else ("1", "2", "3", "4", "5", "6", "7", "8", "9")
        targets = self.target_squares(legal)
        sources = self.source_squares(legal) if self.board_active else {}
        flags = self.board_cell_flags()
        last_to = None if self.last_move is None else self.move_to(self.last_move)
        last_from = None if self.last_move is None else self.move_from(self.last_move)
        for dc in range(9):
            self.board_text(self.BOARD_X + dc * 4, self.BOARD_Y - 1, ranks[dc], M.TEXT_BLACK, M.TEXT_BOLD)
        for dr in range(9):
            y = self.BOARD_Y + dr * 2
            self.board_text(self.BOARD_X - 3, y, files[dr] + " ", M.TEXT_BLACK, M.TEXT_BOLD)
            self.board_text(59, y, files[dr] + " ", M.TEXT_BLACK, M.TEXT_BOLD)
            for dc in range(9):
                p = self.board_cell(dr, dc)
                x = self.BOARD_X + dc * 4
                sq = self.board_index(dr, dc)
                highlight = None
                if self.board_active:
                    if dr == self.cursor_dr and dc == self.cursor_dc:
                        highlight = "cursor"
                    elif targets.get(sq):
                        highlight = "target"
                    elif sources.get(sq):
                        highlight = "source"
                if highlight is None and last_to is not None and (sq == last_to or (last_from is not None and sq == last_from)):
                    highlight = "last"
                if highlight == "cursor":
                    cell_bg = self.cursor_bg()
                elif highlight == "target":
                    cell_bg = self.target_bg()
                elif highlight == "source":
                    cell_bg = self.source_bg()
                elif highlight == "last":
                    cell_bg = self.last_move_bg()
                else:
                    cell_bg = self.board_bg()
                if p == 0:
                    color = M.TEXT_BLACK if highlight == "last" else self.grid_color()
                    self.put_text(x, y, "　", color, flags, cell_bg)
                else:
                    code = p if p > 0 else -p
                    typ = code - 8 if code > 8 else code
                    if code > 8:
                        glyph = PROMOTED_CHARS[typ]
                    elif typ == KING and p < 0:
                        glyph = WHITE_KING_CHAR
                    else:
                        glyph = DISPLAY_CHARS[typ]
                    human_piece = (BLACK if p > 0 else WHITE) == self.human
                    if highlight == "last":
                        color = M.TEXT_BLACK
                    elif human_piece:
                        color = M.TEXT_BLUE
                    else:
                        color = M.TEXT_RED
                    rot = M.TEXT_ROT90 if human_piece else M.TEXT_ROT270
                    self.put_text(x, y, glyph, color, flags | rot, cell_bg)

    def board_index(self, dr, dc):
        if self.human == BLACK:
            return (8 - dc) * 9 + dr
        return dc * 9 + (8 - dr)

    def board_cell(self, dr, dc):
        return self.pos.board[self.board_index(dr, dc)]

    def display_of(self, square):
        if self.human == BLACK:
            return square % 9, 8 - square // 9
        return 8 - square % 9, square // 9

    def active_source(self, legal):
        if self.selected_from is not None:
            return self.selected_from
        if self.selected_drop is not None or not self.board_active:
            return None
        sq = self.board_index(self.cursor_dr, self.cursor_dc)
        return None if not self.moves_from(legal, sq) else sq

    def source_squares(self, legal):
        return {self.move_from(mv): True for mv in legal if mv < DROP_FLAG}

    def target_squares(self, legal):
        targets = {}
        if self.selected_drop is not None:
            for sq in self.drop_targets(legal, self.selected_drop):
                targets[sq] = True
            return targets
        frm = self.active_source(legal)
        if frm is None:
            return targets
        for mv in self.moves_from(legal, frm):
            targets[self.move_to(mv)] = True
        return targets

    def draw_panels(self):
        for y in range(4, 12):
            M.text_put(0, y, " " * 19, M.tattr(M.TEXT_BLACK, self.bg(), 0))
        human_side = "先手" if self.human == BLACK else "後手"
        ai_side = "後手" if self.human == BLACK else "先手"
        self.put_text(0, 2, "あなた", M.TEXT_BRIGHT_BLUE, M.TEXT_BOLD)
        self.put_text(0, 3, human_side + " 持ち駒", M.TEXT_BRIGHT_BLUE)
        types = self.hand_types(self.human)
        if not types:
            self.put_text(0, 4, "-", M.TEXT_BRIGHT_BLUE)
        else:
            for i, t in enumerate(types):
                if i >= 8:
                    break
                label = DISPLAY_CHARS[t] + " x" + str(self.pos.hand(self.human)[t])
                color = M.TEXT_BRIGHT_BLUE
                bgcolor = None
                flags = 0
                if self.menu_focus == "hand" and i == self.hand_index:
                    color = M.TEXT_BLACK
                    bgcolor = self.cursor_bg()
                    flags = M.TEXT_BOLD
                elif self.selected_drop == t:
                    color = M.TEXT_BLACK
                    bgcolor = self.target_bg()
                    flags = M.TEXT_BOLD
                if bgcolor is not None:
                    self.put_text(0, 4 + i, " " * 19, M.TEXT_BLACK, 0, bgcolor)
                self.put_text(0, 4 + i, label, color, flags, bgcolor)
        self.put_text(61, 2, "AI", M.TEXT_BRIGHT_RED, M.TEXT_BOLD)
        self.put_text(61, 3, ai_side + " 持ち駒", M.TEXT_BRIGHT_RED)
        items = self.hand_items(-self.human)
        for i, item in enumerate(items[:8]):
            self.put_text(61, 4 + i, item, M.TEXT_BRIGHT_RED)

    def hand_types(self, side):
        h = self.pos.hand(side)
        return [t for t in range(1, 8) if h[t] > 0]

    def hand_items(self, side):
        h = self.pos.hand(side)
        items = [DISPLAY_CHARS[t] + " x" + str(h[t]) for t in range(1, 8) if h[t] > 0]
        return items if items else ["-"]

    def draw_hint(self, legal):
        self.clear_row(25)
        self.clear_row(26)
        if self.menu_focus == "promotion":
            self.draw_promotion_hint()
            return
        self.put_text(0, 25, "メニュー: ", M.TEXT_BRIGHT_GREEN)
        labels = ("[ヘルプ]", "[投了]", "[終了]")
        xs = (10, 18, 26)
        for i, label in enumerate(labels):
            selected = self.menu_focus == "commands" and self.command_index == i
            if selected:
                self.put_text(xs[i], 25, label, M.TEXT_BLACK, M.TEXT_BOLD, M.TEXT_BRIGHT_BLUE)
            else:
                color = M.TEXT_BRIGHT_WHITE if self.menu_focus == "commands" else M.TEXT_BRIGHT_GREEN
                self.put_text(xs[i], 25, label, color)
        if self.menu_focus == "commands":
            hint = "←→:選択  Enter:決定  ↑:盤面へ"
        elif self.menu_focus == "hand":
            hint = "↑↓:持ち駒  Enter:決定  →:盤面へ"
        elif self.selected_drop is not None:
            hint = "↑↓←→:置く場所  Enter:決定  Tab:取消"
        elif self.selected_from is not None:
            hint = "↑↓←→:移動先  Enter:決定  Tab:取消"
        else:
            hint = "←:持ち駒  ↓:メニュー  Enter:駒を選択"
        self.put_text(0, 26, hint, M.TEXT_BRIGHT_GREEN)

    def draw_promotion_hint(self):
        self.put_text(0, 25, "成りますか？", M.TEXT_BRIGHT_WHITE, M.TEXT_BOLD)
        labels = ("[成らない]", "[成る]")
        xs = (14, 26)
        for i, label in enumerate(labels):
            if self.promotion_index == i:
                self.put_text(xs[i], 25, label, M.TEXT_BLACK, M.TEXT_BOLD, M.TEXT_BRIGHT_BLUE)
            else:
                self.put_text(xs[i], 25, label, M.TEXT_BRIGHT_GREEN)
        self.put_text(0, 26, "←→:選択  Enter:決定  Tab:取消", M.TEXT_BRIGHT_GREEN)

    def draw_message(self):
        self.clear_row(27)
        if self.message is None:
            return
        color = self.message_color or M.TEXT_BLUE
        if color == M.TEXT_BLUE:
            color = M.TEXT_BRIGHT_BLUE
        if color == M.TEXT_RED:
            color = M.TEXT_BRIGHT_RED
        self.put_text(0, 27, self.message, color)

    def turn_text(self):
        side = "先手" if self.pos.turn == BLACK else "後手"
        who = "あなた" if self.pos.turn == self.human else "AI"
        return side + "（" + who + "）の番"

    def menu_help(self):
        return "矢印:移動  Enter:選択/決定  左端←:持ち駒  下端↓:メニュー  Tab:切替"

    def draw_menu(self, legal):
        self.sync_board_mode(legal)
        self.draw_board(legal)
        self.draw_panels()
        self.draw_hint(legal)
        self.draw_message()

    def human_move(self, legal):
        while True:
            key = self.read_key()
            if key is None:
                return None
            if key == self.KEY_TAB:
                self.cycle_focus()
            elif self.menu_focus == "promotion":
                mv = self.promotion_key(key)
                if mv is not None:
                    return mv
            elif self.menu_focus == "commands":
                if key == self.KEY_LEFT:
                    self.command_index = (self.command_index + 2) % 3
                elif key == self.KEY_RIGHT:
                    self.command_index = (self.command_index + 1) % 3
                elif key == self.KEY_UP:
                    self.menu_focus = "board"
                    self.message = None
                elif key == self.KEY_ENTER or key == self.KEY_SPACE:
                    if self.command_index == 0:
                        self.message = self.menu_help()
                        self.message_color = M.TEXT_BLUE
                        self.menu_focus = "board"
                    elif self.command_index == 1:
                        self.message = "投了しました。"
                        self.message_color = M.TEXT_BLUE
                        self.show(legal)
                        return None
                    else:
                        self.message = "終了します。"
                        self.message_color = M.TEXT_BLUE
                        self.show(legal)
                        return None
            elif self.menu_focus == "hand":
                self.hand_key(key, legal)
            elif self.menu_focus == "board":
                mv = self.board_key(key, legal)
                if mv is not None:
                    return mv
            self.draw_menu(legal)

    def cycle_focus(self):
        if self.menu_focus == "promotion":
            self.promotion_moves = None
            self.promotion_index = 0
            self.menu_focus = "board"
            self.message = None
        elif self.menu_focus == "board":
            self.enter_commands()
        elif self.menu_focus == "hand":
            self.menu_focus = "board"
            self.message = None
        else:
            self.selected_from = None
            self.selected_drop = None
            self.menu_focus = "board"
            self.message = None

    def board_key(self, key, legal):
        if key == self.KEY_UP:
            if self.cursor_dr > 0:
                self.cursor_dr -= 1
            self.message = None
        elif key == self.KEY_DOWN:
            if self.cursor_dr < 8:
                self.cursor_dr += 1
                self.message = None
            else:
                self.enter_commands()
        elif key == self.KEY_LEFT:
            if self.cursor_dc > 0:
                self.cursor_dc -= 1
                self.message = None
            else:
                self.enter_hand()
        elif key == self.KEY_RIGHT:
            if self.cursor_dc < 8:
                self.cursor_dc += 1
            self.message = None
        elif key == self.KEY_ENTER or key == self.KEY_SPACE:
            return self.board_enter(legal)
        return None

    def enter_hand(self):
        types = self.hand_types(self.human)
        if not types:
            self.message = "持ち駒はありません。"
            self.message_color = M.TEXT_RED
            return None
        idx = None
        if self.selected_drop is not None:
            for i, t in enumerate(types):
                if t == self.selected_drop:
                    idx = i
        self.hand_index = 0 if idx is None else idx
        self.selected_from = None
        self.selected_drop = None
        self.promotion_moves = None
        self.promotion_index = 0
        self.menu_focus = "hand"
        self.message = None
        return None

    def enter_commands(self):
        self.selected_from = None
        self.selected_drop = None
        self.promotion_moves = None
        self.promotion_index = 0
        self.command_index = 0
        self.menu_focus = "commands"
        self.message = None
        return None

    def hand_key(self, key, legal):
        types = self.hand_types(self.human)
        if not types:
            self.menu_focus = "board"
            return
        if self.hand_index < 0 or self.hand_index >= len(types):
            self.hand_index = 0
        if key == self.KEY_UP:
            self.hand_index = (self.hand_index + len(types) - 1) % len(types)
            self.message = None
        elif key == self.KEY_DOWN:
            self.hand_index = (self.hand_index + 1) % len(types)
            self.message = None
        elif key == self.KEY_RIGHT:
            self.menu_focus = "board"
            self.message = None
        elif key == self.KEY_ENTER or key == self.KEY_SPACE:
            typ = types[self.hand_index]
            targets = self.drop_targets(legal, typ)
            if not targets:
                self.message = "その持ち駒は置ける場所がありません。"
                self.message_color = M.TEXT_RED
            else:
                self.selected_drop = typ
                self.selected_from = None
                self.promotion_moves = None
                self.cursor_dr, self.cursor_dc = self.display_of(targets[0])
                self.menu_focus = "board"
                self.message = "置く場所を選んでください。"
                self.message_color = M.TEXT_BLUE
        return None

    def board_enter(self, legal):
        sq = self.board_index(self.cursor_dr, self.cursor_dc)
        if self.selected_drop is not None:
            mv = DROP_FLAG + self.selected_drop * 100 + sq
            if mv in legal:
                self.selected_drop = None
                self.message = None
                return mv
            self.message = "そこには置けません。"
            self.message_color = M.TEXT_RED
            return None
        if self.selected_from is None:
            moves = self.moves_from(legal, sq)
            if not moves:
                self.message = "この駒は動かせません。"
                self.message_color = M.TEXT_RED
                return None
            self.selected_from = sq
            self.message = "移動先を選んでください。"
            self.message_color = M.TEXT_BLUE
            return None
        if sq == self.selected_from:
            self.selected_from = None
            self.promotion_moves = None
            self.message = None
            return None
        moves = self.moves_between(legal, self.selected_from, sq)
        if not moves:
            other = self.moves_from(legal, sq)
            if not other:
                self.message = "そこへは動かせません。"
                self.message_color = M.TEXT_RED
            else:
                self.selected_from = sq
                self.message = "移動先を選んでください。"
                self.message_color = M.TEXT_BLUE
            return None
        if len(moves) == 1:
            self.selected_from = None
            self.promotion_moves = None
            self.message = None
            return moves[0]
        unpromoted = None
        promoted = None
        for mv in moves:
            if mv >= PROMOTE_FLAG:
                promoted = mv
            else:
                unpromoted = mv
        self.promotion_moves = []
        if unpromoted is not None:
            self.promotion_moves.append(unpromoted)
        if promoted is not None:
            self.promotion_moves.append(promoted)
        self.promotion_index = 0
        self.menu_focus = "promotion"
        self.message = None
        return None

    def promotion_key(self, key):
        if not self.promotion_moves:
            return None
        if key == self.KEY_LEFT or key == self.KEY_RIGHT:
            self.promotion_index = (self.promotion_index + 1) % len(self.promotion_moves)
        elif key == self.KEY_ENTER or key == self.KEY_SPACE:
            mv = self.promotion_moves[self.promotion_index]
            self.selected_from = None
            self.selected_drop = None
            self.promotion_moves = None
            self.promotion_index = 0
            self.menu_focus = "board"
            self.message = None
            return mv
        return None

    def ai_move(self, legal):
        book = self.opening_book_move(legal)
        if book is not None:
            self.message = "AI: " + move_to_usi(book) + "（定跡）"
            self.message_color = M.TEXT_RED
            self.draw_message()
            return book
        self.message = "AI思考中..."
        self.message_color = M.TEXT_BLUE
        self.draw_message()
        t0 = M.ms()
        mv = self.engine.choose_move(self.pos)
        elapsed = M.ms() - t0
        if mv is None:
            return None
        self.message = ("AI: " + move_to_usi(mv) + "（深さ " + str(self.engine.depth)
                        + "、 " + str(self.engine.nodes) + " ノード、 " + str(elapsed) + " ms）")
        self.message_color = M.TEXT_RED
        self.draw_message()
        return mv

    def opening_book_move(self, legal):
        if self.pos.in_check(self.pos.turn):
            return None
        if self.pos.turn == BLACK:
            if self.pos.move_number == 1:
                names = ("7g7f", "2g2f")
            elif self.pos.move_number == 3:
                names = ("2g2f", "6g6f", "5g5f")
            else:
                names = None
        else:
            if self.pos.move_number == 2:
                names = ("3c3d", "8c8d")
            elif self.pos.move_number == 4:
                names = ("8c8d", "2b3c", "5c5d")
            else:
                names = None
        if names is None:
            return None
        for name in names:
            moves = parse_move(name, legal)
            if moves:
                return moves[0]
        return None

    def show_result(self, legal=None):
        side = self.pos.turn
        if self.pos.in_check(side):
            if side == self.human:
                self.message = "詰みました。あなたの負けです。"
                self.message_color = M.TEXT_RED
            else:
                self.message = "詰みました。あなたの勝ちです！"
                self.message_color = M.TEXT_BLUE
        else:
            if side == self.human:
                self.message = "指せる手がありません。あなたの負けです。"
                self.message_color = M.TEXT_RED
            else:
                self.message = "指せる手がありません。あなたの勝ちです。"
                self.message_color = M.TEXT_BLUE
        self.show(legal)
        self.clear_row(27)
        self.clear_row(23)
        self.clear_row(24)
        self.put_text(0, 23, "対局ありがとうございました。", M.TEXT_MAGENTA)
        self.put_text(0, 24, self.message, M.TEXT_MAGENTA)

# ---- 起動 ----
M.mode = 1
M.clear_keys()
M.text_clear(M.TEXT_CLEAR)
game = Game()
game.run()
print("bye")
