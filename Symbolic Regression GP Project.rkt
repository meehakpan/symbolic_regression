#lang racket/base

(require racket/list
         racket/match
         racket/vector)

;For any new function defined for the function set, It must be added to this namespace
(define eval-ns (make-base-namespace))

; WHAT TODO: Supports functions of arities other than 2
(define function-set
  '(+ - *))

; WHAT TODO: You must allow terminals with different probabilities of occuring in random-terminal
(define terminal-set
  '(x x x 1 2 3 4 5 6 7 8 9))

; Note: For any serious use of symbolic regression, we would load a set of points instead of generating them
(define (test-function x)
  (+ (* 5 x x) (* -9 x)))
(define test-domain (range -10 11 2))
(define test-values (map test-function test-domain))

(define (random-function)
  (car (shuffle function-set)))

(define (random-terminal)
  (car (shuffle terminal-set)))

;; ---------------------------------------------------------------------------------------------------
;; FOR TREE OPERATIONS

(define (full-tree depth)
  (define (make-full-tree level)
    (if (= level depth)
        (random-terminal)
        (list (random-function) (make-full-tree (+ level 1)) (make-full-tree (+ level 1)))))
  (make-full-tree 0))

(define (grow-tree depth)
  (define (make-grow-tree level)
    (cond
      [(= level depth) (random-terminal)]
      [(and (eq? 0 (random 3)) (not (eq? 0 level))) (random-terminal)]
      [else (list (random-function) (make-grow-tree (+ level 1)) (make-grow-tree (+ level 1)))]))
  (make-grow-tree 0))

(define (random-subtree tree)
  (define (foo tree path)
    (match tree
      [`(,func ,left ,right)
       (if (and (= 0 (random 2)) (not (null? path)))
           (values tree path)
           (if (= 0 (random 2))
               (foo left (cons 'left path))
               (foo right (cons 'right path))))]
      [terminal (values terminal path)]))
  (let-values ([(subtree path) (foo tree '())])
    (values subtree (reverse path))))

(define (replace-subtree tree new-subtree path)
  (cond
    [(null? path) new-subtree]
    [(match-let ([`(,func ,left ,right) tree])
      (if (eq? (car path) 'left)
          `(,func ,(replace-subtree left new-subtree (cdr path)) ,right)
          `(,func ,left ,(replace-subtree right new-subtree (cdr path)))))]))

;WHAT TODO: Implement some of the fancier mutation operators
(define (mutate tree)
  (let-values ([(subtree path) (random-subtree tree)])
    (replace-subtree tree
                     (grow-tree (random 4))
                     path)))

(define (crossover tree1 tree2)
  (let-values ([(subtree1 path1) (random-subtree tree1)]
               [(subtree2 path2) (random-subtree tree2)])
    (values (replace-subtree tree1 subtree2 path1)
            (replace-subtree tree2 subtree1 path2))))

;; ---------------------------------------------------------------------------------------------------
;;FOR TREE OPERATIONS II

; You have creates a mixture of full and uneven trees of depths 2-6
(define (ramped-half-and-half)
  (for*/vector ([size '(2 3 4 5 6)]
                [method '(full grow)]
                [quantity (range 0 50)])
    (match method
      ['full (full-tree size)]
      ['grow (grow-tree size)])))

; Note: You are at liberty to choose any variable so long as it is named x
(define (evaluate-fitness tree)
  (let* ([f (λ (x)
              (namespace-set-variable-value! 'x x #f eval-ns)
              (eval tree eval-ns))]
         [output (map f test-domain)])
    (foldl (λ (x y acc) (+ acc
                           (abs (- x y))))
           0
           output
           test-values)))

(struct EvaluatedProgram
  (tree fitness))

(define (evaluate-programs vec)
  (vector-map! (λ (tree) (EvaluatedProgram tree (evaluate-fitness tree)))
               vec))

; It finds the n most fit programs in a cohort
; WHAT TODO: there better ways do this, I think so probably!
(define (n-most-fit n vec)
  (let* ([ls (vector->list vec)]
         [sorted (sort ls (λ (p1 p2) (< (EvaluatedProgram-fitness p1)
                                        (EvaluatedProgram-fitness p2))))])
    (take sorted n)))

; Tournament selection for crossover (460)
; Survival of the fittest (top 20)
; Mutation (20)

; TWO TREES ENTER, ONE TREE LEAVES
(define (tournament-round prog1 prog2)
  (let-values ([(tree1 tree2) (crossover (EvaluatedProgram-tree prog1)
                                         (EvaluatedProgram-tree prog2))])
    (if (< (EvaluatedProgram-fitness prog1) (EvaluatedProgram-fitness prog2))
        tree1
        tree2)))

; Returns two distinct random nonnegative integers from the interval [0, bound)
; Note: Do not call it with a bound of 1, that would be bad
(define (distinct-randoms bound)
  (let ([x (random bound)]
        [y (random bound)])
    (if (= x y)
        (distinct-randoms bound)
        (values x y))))

(define (next-generation vec)
  (define foo (make-vector 500))
  (define champions (n-most-fit 20 vec))
  (for ([i (range 0 460)])
    (let-values ([(n1 n2) (distinct-randoms 500)])
      (let ([tree (tournament-round (vector-ref vec n1) (vector-ref vec n2))])
        (vector-set! foo i tree))))
  (for ([i (range 460 480)])
    (vector-set! foo i (EvaluatedProgram-tree (list-ref champions (- i 460)))))
  (for ([i (range 480 500)])
    (vector-set! foo i (mutate (EvaluatedProgram-tree (vector-ref vec (random 500))))))
  foo)

;; ---------------------------------------------------------------------------------------------------
;; Now this where stuff actually happens

(define run-gp
  (λ (#:max-generations [max-generations 50])
    (define (run population generation)
      (evaluate-programs population)
      (let* ([leaders (n-most-fit 10 population)]
             [peak-fitness (EvaluatedProgram-fitness (car leaders))]
             [best-program (EvaluatedProgram-tree (car leaders))])
        (displayln (string-append "Generation " (number->string generation)))
        (cond
          [(= peak-fitness 0) (displayln "Solution found!")
                              (displayln best-program)]
          [else (display "Top fitness scores: ")
                (displayln (map EvaluatedProgram-fitness leaders))
                (display "\n")
                (cond
                  [(= generation max-generations)
                   (displayln (string-append "No solution found in "
                                             (number->string max-generations)
                                             " generations."))
                   (display "Most fit solution: ")
                   (displayln best-program)]
                  [else (run (next-generation population) (+ generation 1))])])))
    (run (ramped-half-and-half) 1)))

; Let's use hill climbing as an alternative to gp, a real life scenario!
(define hill-climb
  (λ (#:max-iterations [max-iterations 10000])
    (define (climb tree fitness count)
      (let* ([mutated-tree (mutate tree)]
             [mutated-fitness (evaluate-fitness mutated-tree)])
        (cond
          [(zero? mutated-fitness) (values 'success mutated-tree count)]
          [(= count max-iterations) (values 'fail mutated-tree count)]
          [(< mutated-fitness fitness) (climb mutated-tree mutated-fitness (add1 count))]
          [else (climb tree fitness (add1 count))])))
    (define-values (status result iterations)
      (let* ([tree (full-tree 3)]
             [fitness (evaluate-fitness tree)])
        (climb tree fitness 1)))
    (match status
      ['success (displayln (string-append "Program found for 5x² - 3x + 8 in "
                                          (number->string iterations)
                                          " iterations"))
                (displayln result)]
      ['fail (displayln (string-append "Terminated after "
                                       (number->string iterations)
                                       " iterations, no result found"))])))
